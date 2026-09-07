require 'rails_helper'

describe CareQueueListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }
  let(:whale) { create(:contact, account: account, identifier: 'a1' * 12, custom_attributes: { 'segment_weight' => 'Whale' }) }
  let(:conversation) { create(:conversation, account: account, contact: whale, status: :open) }

  def event(name, conversation)
    Events::Base.new(name, Time.zone.now, conversation: conversation)
  end

  it 'enqueues the queue job on created/opened for contacts with a segment' do
    with_modified_env(env) do
      expect(Care::Queue::ConversationJob).to receive(:perform_later).with(conversation.id, 'conversation_created').once
      expect(Care::Queue::ConversationJob).to receive(:perform_later).with(conversation.id, 'conversation_opened').once
      listener.conversation_created(event('conversation.created', conversation))
      listener.conversation_opened(event('conversation.opened', conversation))
    end
  end

  it 'ignores contacts without a segment — the contact job catches them after the sync' do
    plain = create(:conversation, account: account, status: :open)
    with_modified_env(env) do
      expect(Care::Queue::ConversationJob).not_to receive(:perform_later)
      listener.conversation_created(event('conversation.created', plain))
      listener.conversation_opened(event('conversation.opened', plain))
    end
  end

  it 'reacts to resolve only when the conversation has an active tracker' do
    allow(Care::Queue::ConversationJob).to receive(:perform_later)
    with_modified_env(env) do
      listener.conversation_resolved(event('conversation.resolved', conversation))
      expect(Care::Queue::ConversationJob).not_to have_received(:perform_later)

      Care::SlaTracker.create!(account: account, conversation: conversation, contact: whale, class_key: 'vip', class_name: 'VIP',
                               started_at: 1.minute.ago)
      listener.conversation_resolved(event('conversation.resolved', conversation))
      expect(Care::Queue::ConversationJob).to have_received(:perform_later).with(conversation.id, 'conversation_resolved').once
    end
  end

  it 'does nothing when disabled or for another account' do
    expect(Care::Queue::ConversationJob).not_to receive(:perform_later)
    listener.conversation_created(event('conversation.created', conversation))
    with_modified_env(env.merge(CARE_SEGMENT_SYNC_ACCOUNT_ID: (account.id + 1).to_s)) do
      listener.conversation_opened(event('conversation.opened', conversation))
    end
  end
end
