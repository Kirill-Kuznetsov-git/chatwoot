require 'rails_helper'

RSpec.describe Internal::RemoveStaleContactInboxesService do
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

    it 'deletes stale contact inboxes older than 90 days by default' do
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true' do
        create(:contact_inbox, created_at: 3.days.ago)
        create(:contact_inbox, created_at: 89.days.ago)
        create(:contact_inbox, created_at: 91.days.ago)
        create(:contact_inbox, created_at: 92.days.ago)
        create(:contact_inbox, created_at: 93.days.ago)
        create(:contact_inbox, created_at: 94.days.ago)

        service = described_class.new
        expect { service.perform }.to change(ContactInbox, :count).by(-4)
      end
    end

    it 'respects REMOVE_STALE_CONTACT_INBOX_DAYS' do
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: '14' do
        fresh = create(:contact_inbox, created_at: 13.days.ago)
        stale = create(:contact_inbox, created_at: 15.days.ago)
        very_stale = create(:contact_inbox, created_at: 200.days.ago)

        expect(described_class.new.perform).to eq(2)
        expect(ContactInbox.exists?(fresh.id)).to be(true)
        expect(ContactInbox.exists?(stale.id)).to be(false)
        expect(ContactInbox.exists?(very_stale.id)).to be(false)
      end
    end

    it 'never deletes contact inboxes that have conversations, regardless of age' do
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: '14' do
        with_conversation = create(:contact_inbox, created_at: 400.days.ago)
        create(:conversation, contact_inbox: with_conversation, contact: with_conversation.contact, inbox: with_conversation.inbox,
                              account: with_conversation.inbox.account)
        resolved = create(:contact_inbox, created_at: 400.days.ago)
        create(:conversation, contact_inbox: resolved, contact: resolved.contact, inbox: resolved.inbox,
                              account: resolved.inbox.account, status: :resolved)
        empty = create(:contact_inbox, created_at: 400.days.ago)

        expect(described_class.new.perform).to eq(1)
        expect(ContactInbox.exists?(with_conversation.id)).to be(true)
        expect(ContactInbox.exists?(resolved.id)).to be(true)
        expect(ContactInbox.exists?(empty.id)).to be(false)
        expect(Conversation.where.missing(:contact_inbox).count).to eq(0)
      end
    end

    it 'deletes across several batches' do
      stub_const('Internal::RemoveStaleContactInboxesService::BATCH_SIZE', 2)
      with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: '7' do
        5.times { create(:contact_inbox, created_at: 10.days.ago) }
        kept = create(:contact_inbox, created_at: 10.days.ago)
        create(:conversation, contact_inbox: kept, contact: kept.contact, inbox: kept.inbox, account: kept.inbox.account)

        expect(described_class.new.perform).to eq(5)
        expect(ContactInbox.exists?(kept.id)).to be(true)
        expect(ContactInbox.count).to eq(1)
      end
    end

    it 'falls back to the default retention when REMOVE_STALE_CONTACT_INBOX_DAYS is invalid' do
      %w[0 -5 abc].each do |bad_value|
        with_modified_env REMOVE_STALE_CONTACT_INBOX_JOB_STATUS: 'true', REMOVE_STALE_CONTACT_INBOX_DAYS: bad_value do
          recent = create(:contact_inbox, created_at: 1.day.ago)
          old = create(:contact_inbox, created_at: 91.days.ago)

          allow(Rails.logger).to receive(:error).and_call_original
          expect(described_class.new.perform).to eq(1)
          expect(Rails.logger).to have_received(:error).with(/invalid REMOVE_STALE_CONTACT_INBOX_DAYS=#{Regexp.escape(bad_value.inspect)}/)
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
