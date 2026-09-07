require 'rails_helper'

describe CareSegmentListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:identifier) { 'd4' * 12 }
  let(:contact) { create(:contact, account: account, identifier: identifier) }
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }

  def event(name, **data)
    Events::Base.new(name, Time.zone.now, **data)
  end

  describe '#contact_updated' do
    it 'enqueues a sync when the identifier was set' do
      with_modified_env(env) do
        expect(Care::SegmentSyncJob).to receive(:perform_later).with(contact.id).once
        listener.contact_updated(event('contact.updated', contact: contact, changed_attributes: { 'identifier' => [nil, identifier] }))
      end
    end

    it 'ignores updates that did not touch the identifier' do
      with_modified_env(env) do
        expect(Care::SegmentSyncJob).not_to receive(:perform_later)
        listener.contact_updated(event('contact.updated', contact: contact, changed_attributes: { 'name' => %w[a b] }))
        listener.contact_updated(event('contact.updated', contact: contact, changed_attributes: nil))
      end
    end

    it 'ignores contacts without a StarPets identifier' do
      email_only = create(:contact, :with_email, account: account)
      with_modified_env(env) do
        expect(Care::SegmentSyncJob).not_to receive(:perform_later)
        listener.contact_updated(event('contact.updated', contact: email_only, changed_attributes: { 'identifier' => [nil, 'x'] }))
      end
    end

    it 'does nothing when disabled or for another account' do
      expect(Care::SegmentSyncJob).not_to receive(:perform_later)
      listener.contact_updated(event('contact.updated', contact: contact, changed_attributes: { 'identifier' => [nil, identifier] }))
      with_modified_env(env.merge(CARE_SEGMENT_SYNC_ACCOUNT_ID: (account.id + 1).to_s)) do
        listener.contact_updated(event('contact.updated', contact: contact, changed_attributes: { 'identifier' => [nil, identifier] }))
      end
    end
  end

  describe '#contact_created' do
    it 'enqueues a sync for an identified contact' do
      with_modified_env(env) do
        expect(Care::SegmentSyncJob).to receive(:perform_later).with(contact.id).once
        listener.contact_created(event('contact.created', contact: contact))
      end
    end
  end

  describe '#conversation_created' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'enqueues a sync when the contact has no fresh segment' do
      with_modified_env(env) do
        expect(Care::SegmentSyncJob).to receive(:perform_later).with(contact.id).once
        listener.conversation_created(event('conversation.created', conversation: conversation))
      end
    end

    it 'does not enqueue when the segment is fresh' do
      contact.update!(custom_attributes: { 'segment_synced_at' => 5.minutes.ago.utc.iso8601 })
      with_modified_env(env) do
        expect(Care::SegmentSyncJob).not_to receive(:perform_later)
        listener.conversation_created(event('conversation.created', conversation: conversation))
      end
    end
  end

  it 'is registered in the async dispatcher' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end
end
