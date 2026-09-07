require 'rails_helper'

describe Care::SegmentSync do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, identifier: 'a1' * 12) }
  let(:segment) do
    { 'role' => 'Seller', 'weight' => 'Big Whale', 'tier_90d' => 'Medium', 'label' => '🐋 Big Whale Seller',
      'priority_rank' => 11, 'source' => 'metabase' }
  end

  describe '.enabled?' do
    it 'requires the flag, the url and the key' do
      with_modified_env(CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k') do
        expect(described_class.enabled?).to be true
      end
      with_modified_env(CARE_SEGMENT_SYNC_ENABLED: 'false', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k') do
        expect(described_class.enabled?).to be false
      end
      with_modified_env(CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: nil, CARE_SERVICE_KEY: 'k') do
        expect(described_class.enabled?).to be false
      end
      with_modified_env(CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: nil) do
        expect(described_class.enabled?).to be false
      end
    end
  end

  describe '.account_allowed?' do
    it 'allows everything when not restricted and only the configured account otherwise' do
      with_modified_env(CARE_SEGMENT_SYNC_ACCOUNT_ID: nil) { expect(described_class.account_allowed?(7)).to be true }
      with_modified_env(CARE_SEGMENT_SYNC_ACCOUNT_ID: '7') do
        expect(described_class.account_allowed?(7)).to be true
        expect(described_class.account_allowed?(8)).to be false
      end
    end
  end

  describe '.identifier_valid?' do
    it 'accepts only 24-hex StarPets ids' do
      expect(described_class.identifier_valid?('a1' * 12)).to be true
      expect(described_class.identifier_valid?('A1' * 12)).to be false
      expect(described_class.identifier_valid?('a1' * 11)).to be false
      expect(described_class.identifier_valid?(nil)).to be false
      expect(described_class.identifier_valid?('user@example.com')).to be false
    end
  end

  describe '.fresh?' do
    it 'is false without a stamp, with garbage, or when older than a day' do
      expect(described_class.fresh?(contact)).to be false
      contact.update!(custom_attributes: { 'segment_synced_at' => 'garbage' })
      expect(described_class.fresh?(contact)).to be false
      contact.update!(custom_attributes: { 'segment_synced_at' => 25.hours.ago.utc.iso8601 })
      expect(described_class.fresh?(contact)).to be false
    end

    it 'is true within a day' do
      contact.update!(custom_attributes: { 'segment_synced_at' => 1.hour.ago.utc.iso8601 })
      expect(described_class.fresh?(contact)).to be true
    end
  end

  describe '.attributes_for' do
    it 'maps the Care response to contact attribute keys' do
      expect(described_class.attributes_for(segment)).to eq(
        'segment_role' => 'Seller', 'segment_weight' => 'Big Whale', 'segment_tier_90d' => 'Medium',
        'segment_label' => '🐋 Big Whale Seller', 'segment_priority' => 11
      )
    end
  end

  describe '.apply!' do
    let(:values) { described_class.attributes_for(segment) }
    let(:now) { Time.zone.parse('2026-09-07T01:00:00Z') }

    it 'writes the segment, keeps foreign attributes and stamps synced_at' do
      contact.update!(custom_attributes: { 'starpets_id' => contact.identifier, 'language' => 'ru' })

      expect(described_class.apply!(contact, values, now: now)).to be true
      contact.reload
      expect(contact.custom_attributes).to include(
        'starpets_id' => contact.identifier, 'language' => 'ru',
        'segment_role' => 'Seller', 'segment_weight' => 'Big Whale', 'segment_tier_90d' => 'Medium',
        'segment_label' => '🐋 Big Whale Seller', 'segment_priority' => 11,
        'segment_synced_at' => '2026-09-07T01:00:00Z'
      )
    end

    it 'removes the tier key when the segment has no tier (Newcomer)' do
      described_class.apply!(contact, values, now: now)
      newcomer = values.merge('segment_role' => 'Newcomer', 'segment_tier_90d' => nil)

      expect(described_class.apply!(contact, newcomer, now: now)).to be true
      expect(contact.reload.custom_attributes).not_to have_key('segment_tier_90d')
      expect(contact.custom_attributes['segment_role']).to eq('Newcomer')
    end

    it 'only refreshes the stamp silently when nothing changed' do
      described_class.apply!(contact, values, now: now)
      later = now + 2.hours

      expect(contact).not_to receive(:update!)
      expect(described_class.apply!(contact, values, now: later)).to be false
      expect(contact.reload.custom_attributes['segment_synced_at']).to eq('2026-09-07T03:00:00Z')
      expect(contact.custom_attributes['segment_label']).to eq('🐋 Big Whale Seller')
    end
  end
end
