require 'rails_helper'

RSpec.describe Internal::RemoveStaleContactInboxesService do
  def conversation_for(contact_inbox, **attrs)
    create(:conversation, contact_inbox: contact_inbox, contact: contact_inbox.contact, inbox: contact_inbox.inbox,
                          account: contact_inbox.inbox.account, **attrs)
  end

  describe '#perform' do
    it 'does not delete stale contact inboxes if REMOVE_STALE_CONTACT_INBOX_JOB_STATUS is false' do
      # default value of REMOVE_STALE_CONTACT_INBOX_JOB_STATUS is false
      create(:contact_inbox, created_at: 3.days.ago)
      create(:contact_inbox, created_at: 91.days.ago)
      create(:contact_inbox, created_at: 92.days.ago)
      create(:contact_inbox, created_at: 93.days.ago)
      create(:contact_inbox, created_at: 94.days.ago)

      service = described_class.new
      expect { service.perform }.not_to change(ContactInbox, :count)
    end

    it 'deletes contact inboxes aged between 90 and 97 days by default' do
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true' do
        create(:contact_inbox, created_at: 3.days.ago)
        create(:contact_inbox, created_at: 89.days.ago)
        create(:contact_inbox, created_at: 91.days.ago)
        create(:contact_inbox, created_at: 92.days.ago)
        create(:contact_inbox, created_at: 93.days.ago)
        create(:contact_inbox, created_at: 96.days.ago)

        service = described_class.new
        expect { service.perform }.to change(ContactInbox, :count).by(-4)
      end
    end

    it 'leaves contact inboxes older than the window untouched' do
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true' do
        beyond_window = create(:contact_inbox, created_at: 98.days.ago)
        inside_window = create(:contact_inbox, created_at: 95.days.ago)

        expect(described_class.new.perform).to eq(1)
        expect(ContactInbox.exists?(beyond_window.id)).to be(true)
        expect(ContactInbox.exists?(inside_window.id)).to be(false)
      end
    end

    it 'respects REMOVE_STALE_CONTACT_INBOX_DAYS and REMOVE_STALE_CONTACT_INBOX_WINDOW_DAYS' do
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: '14',
                        REMOVE_STALE_CONTACT_INBOX_WINDOW_DAYS: '30' do
        fresh = create(:contact_inbox, created_at: 13.days.ago)
        stale = create(:contact_inbox, created_at: 15.days.ago)
        older_inside_window = create(:contact_inbox, created_at: 43.days.ago)
        beyond_window = create(:contact_inbox, created_at: 45.days.ago)

        expect(described_class.new.perform).to eq(2)
        expect(ContactInbox.exists?(fresh.id)).to be(true)
        expect(ContactInbox.exists?(stale.id)).to be(false)
        expect(ContactInbox.exists?(older_inside_window.id)).to be(false)
        expect(ContactInbox.exists?(beyond_window.id)).to be(true)
      end
    end

    it 'never deletes contact inboxes that have conversations, regardless of status' do
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: '14' do
        with_conversation = create(:contact_inbox, created_at: 16.days.ago)
        conversation_for(with_conversation)
        resolved = create(:contact_inbox, created_at: 16.days.ago)
        conversation_for(resolved, status: :resolved)
        empty = create(:contact_inbox, created_at: 16.days.ago)

        expect(described_class.new.perform).to eq(1)
        expect(ContactInbox.exists?(with_conversation.id)).to be(true)
        expect(ContactInbox.exists?(resolved.id)).to be(true)
        expect(ContactInbox.exists?(empty.id)).to be(false)
        expect(Conversation.where.missing(:contact_inbox).count).to eq(0)
      end
    end

    it 'deletes across several batches, moving the cursor and skipping contact inboxes with conversations' do
      stub_const('Internal::RemoveStaleContactInboxesService::BATCH_SIZE', 2)
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: '7' do
        kept_first = create(:contact_inbox, created_at: 13.days.ago)
        conversation_for(kept_first)
        (8..12).each { |days| create(:contact_inbox, created_at: days.days.ago) }
        kept_last = create(:contact_inbox, created_at: 8.days.ago)
        conversation_for(kept_last)
        # Одинаковый created_at у соседних строк не должен ломать курсор.
        create_list(:contact_inbox, 2, created_at: 9.days.ago)

        allow(Rails.logger).to receive(:info).and_call_original
        expect(described_class.new.perform).to eq(7)
        expect(ContactInbox.where(id: [kept_first.id, kept_last.id]).count).to eq(2)
        expect(ContactInbox.count).to eq(2)
        expect(Rails.logger).to have_received(:info).with(/batch 4: scanned 2, deleted/)
        expect(Rails.logger).to have_received(:info).with(/finished: deleted 7 contact inboxes in 5 batches/)
      end
    end

    it 'stops when a full batch shares one created_at and every row has a conversation' do
      stub_const('Internal::RemoveStaleContactInboxesService::BATCH_SIZE', 2)
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: '7' do
        same_moment = 10.days.ago
        create_list(:contact_inbox, 2, created_at: same_moment).each { |contact_inbox| conversation_for(contact_inbox) }

        allow(Rails.logger).to receive(:info).and_call_original
        expect(described_class.new.perform).to eq(0)
        expect(ContactInbox.count).to eq(2)
        # Первая порция сдвигает курсор на общий created_at, вторая видит те же строки и останавливается.
        expect(Rails.logger).to have_received(:info).with(/finished: deleted 0 contact inboxes in 2 batches/)
      end
    end

    it 'falls back to the default values when the env vars are invalid' do
      %w[0 -5 abc].each do |bad_value|
        with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: bad_value,
                          REMOVE_STALE_CONTACT_INBOX_WINDOW_DAYS: bad_value do
          recent = create(:contact_inbox, created_at: 1.day.ago)
          old = create(:contact_inbox, created_at: 91.days.ago)

          allow(Rails.logger).to receive(:error).and_call_original
          expect(described_class.new.perform).to eq(1)
          expect(Rails.logger).to have_received(:error).with(/invalid REMOVE_STALE_CONTACT_INBOX_DAYS=#{Regexp.escape(bad_value.inspect)}/)
          expect(Rails.logger).to have_received(:error).with(/invalid REMOVE_STALE_CONTACT_INBOX_WINDOW_DAYS=#{Regexp.escape(bad_value.inspect)}/)
          expect(ContactInbox.exists?(recent.id)).to be(true)
          expect(ContactInbox.exists?(old.id)).to be(false)
        end
      end
    end

    it 'warns when conversations without contact inbox exist after the run' do
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true' do
        conversation = create(:conversation)
        # Осиротевший диалог можно получить только мимо валидаций belongs_to.
        conversation.update_column(:contact_inbox_id, conversation.contact_inbox_id + 1_000_000) # rubocop:disable Rails/SkipsModelValidations

        allow(Rails.logger).to receive(:warn).and_call_original
        described_class.new.perform
        expect(Rails.logger).to have_received(:warn).with(/orphan check: 1 conversations without contact inbox/)
      end
    end
  end
end
