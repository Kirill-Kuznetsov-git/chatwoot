require 'rails_helper'

RSpec.describe Conversation do
  self.use_transactional_tests = false

  it 'serializes a label commit ahead of a stale automatic resolution on another database connection' do
    account = create(:account)
    conversation = create(:conversation, account: account).reload
    stale = described_class.find(conversation.id)
    worker = nil
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s) do
      conversation.with_lock do
        conversation.update_labels(['escalated'])
        connection_id = Queue.new
        worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            Current.reset
            ActiveRecord::Base.cache do
              expect(stale.manually_escalated?).to be(false)
              connection_id << connection.select_value('SELECT pg_backend_pid()')
              stale.resolved!
            end
          ensure
            Current.reset
          end
        end
        pid = connection_id.pop
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        loop do
          waiting = ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
          break if waiting == 'Lock'
          raise 'Automatic resolution did not wait for the label row lock' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep 0.01
        end
        expect(conversation.reload.status).to eq('open')
      end
      expect(worker.join(5)).to eq(worker)
      worker.value
      expect(conversation.reload.status).to eq('open')
      expect(conversation.label_list).to include('escalated')
    end
  ensure
    worker&.join(5)
    conversation&.destroy!
    account&.destroy!
  end

  it 'rejects a queued public bot reply after a concurrent manual tag commit' do
    account = create(:account)
    conversation = create(:conversation, account: account).reload
    bot = create(:agent_bot, account: account)
    worker = nil
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s) do
      conversation.with_lock do
        conversation.update_labels(['escalated'])
        connection_id = Queue.new
        worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            Current.reset
            connection_id << connection.select_value('SELECT pg_backend_pid()')
            Message.create!(conversation: described_class.find(conversation.id), account: account, inbox: conversation.inbox,
                            sender: bot, message_type: :outgoing, content: 'Late bot reply', private: false)
          rescue ActiveRecord::RecordInvalid => e
            e.record.errors.full_messages
          ensure
            Current.reset
          end
        end
        pid = connection_id.pop
        Timeout.timeout(5) do
          until ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == 'Lock'
            sleep 0.01
          end
        end
      end
      expect(worker.join(5)).to eq(worker)
      expect(worker.value).to include('Conversation is held for manual escalation')
      expect(conversation.messages.where(content: 'Late bot reply')).to be_empty
    end
  ensure
    worker&.join(5)
    conversation&.destroy!
    bot&.destroy!
    account&.destroy!
  end
end
