require 'rails_helper'

describe Care::Queue::Config do
  let(:settings) { Care::Queue::Defaults::SETTINGS }
  let(:config) { described_class.new(settings, version: 1, source: 'test') }

  before do
    Redis::Alfred.delete(described_class::CACHE_KEY)
    Redis::Alfred.delete(described_class::LAST_GOOD_KEY)
  end

  describe '#classify' do
    let(:contact) { Struct.new(:custom_attributes) }

    it 'picks the first matching class by weight or tier, in config order' do
      expect(config.classify(contact.new({ 'segment_weight' => 'Mega Whale', 'segment_tier_90d' => 'Big' })).key).to eq('vip')
      expect(config.classify(contact.new({ 'segment_weight' => 'Whale', 'segment_tier_90d' => 'Small' })).key).to eq('vip')
      expect(config.classify(contact.new({ 'segment_weight' => 'Big Fish', 'segment_tier_90d' => 'Medium' })).key).to eq('big')
      expect(config.classify(contact.new({ 'segment_weight' => 'Mid Fish', 'segment_tier_90d' => 'Big' })).key).to eq('big')
    end

    it 'leaves everyone else outside the queue' do
      expect(config.classify(contact.new({ 'segment_weight' => 'Mid Fish', 'segment_tier_90d' => 'Medium' }))).to be_nil
      expect(config.classify(contact.new({ 'segment_weight' => 'No Purchases' }))).to be_nil
      expect(config.classify(contact.new({}))).to be_nil
      expect(config.classify(nil)).to be_nil
    end
  end

  describe '#contact_match_sql' do
    it 'covers every weight and tier of all classes' do
      expect(config.contact_match_sql).to include("'Mega Whale','Big Whale','Whale','Big Fish'", "IN ('Big')")
      expect(described_class.new({ 'classes' => [] }).contact_match_sql).to eq('1 = 0')
    end
  end

  describe '.current' do
    let(:body) { { 'settings' => settings.merge('risk_share' => 0.5), 'version' => 3 } }
    let(:client) { instance_double(Care::Client, queue_config: body) }

    it 'fetches from Care once, then serves the minute cache and keeps a last-good copy' do
      first = described_class.current(client: client)
      second = described_class.current(client: client)

      expect(first).to have_attributes(version: 3, source: 'care', risk_share: 0.5)
      expect(second).to have_attributes(version: 3, source: 'cache', risk_share: 0.5)
      expect(client).to have_received(:queue_config).once
      expect(JSON.parse(Redis::Alfred.get(described_class::LAST_GOOD_KEY))['version']).to eq(3)
    end

    it 'falls back to the last-good copy when Care fails and to built-in defaults when there is none' do
      failing = instance_double(Care::Client)
      allow(failing).to receive(:queue_config).and_raise(Care::Client::Unavailable, 'care: HTTP 503')
      Redis::Alfred.set(described_class::LAST_GOOD_KEY, { 'settings' => settings.merge('risk_share' => 0.6), 'version' => 2 }.to_json)

      from_last_good = described_class.current(client: failing)
      expect(from_last_good).to have_attributes(version: 2, source: 'last_good', risk_share: 0.6)

      Redis::Alfred.delete(described_class::LAST_GOOD_KEY)
      defaults = described_class.current(client: failing)
      expect(defaults).to have_attributes(version: 0, source: 'defaults', risk_share: 0.8, queue_enabled: true, sla_labels_enabled: false)
      expect(defaults.classes.map(&:key)).to eq(%w[vip big])
    end

    it 'invalidate! forces a refetch' do
      described_class.current(client: client)
      described_class.invalidate!
      described_class.current(client: client)
      expect(client).to have_received(:queue_config).twice
    end
  end

  describe 'class parsing' do
    it 'reads targets, flags and defaults for missing fields' do
      vip = config.class_for('vip')
      expect(vip).to have_attributes(chatwoot_priority: 'urgent', labels: ['vip'], sla_enabled: true, first_response_minutes: 30,
                                     next_response_minutes: 60, resolution_minutes: 720, alert_on_breach: true,
                                     escalate_priority_on_breach: nil)
      bare = described_class.new({ 'classes' => [{ 'key' => 'x', 'tiers' => ['Big'] }] }).class_for('x')
      expect(bare).to have_attributes(name: 'x', weights: [], chatwoot_priority: nil, labels: [], sla_enabled: true,
                                      first_response_minutes: nil, alert_on_breach: false)
    end
  end
end
