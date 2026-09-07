require 'rails_helper'

describe Care::Client do
  let(:client) { described_class.new(base_url: 'https://care.test/', key: 'svc_key') }
  let(:user_id) { 'b2' * 12 }
  let(:url) { "https://care.test/api/users/#{user_id}/segment" }
  let(:body) { { role: 'Buyer', weight: 'Whale', tier_90d: 'Big', label: '🦈 Whale Buyer', priority_rank: 20, source: 'metabase' } }

  it 'fetches the segment with the service key' do
    stub = stub_request(:get, url).with(headers: { 'Authorization' => 'Bearer svc_key' })
                                  .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(client.segment(user_id)).to include('role' => 'Buyer', 'weight' => 'Whale', 'priority_rank' => 20)
    expect(stub).to have_been_requested.once
  end

  it 'raises Unauthorized on 401/403' do
    stub_request(:get, url).to_return(status: 403, body: '{"detail":{"code":"FORBIDDEN"}}')
    expect { client.segment(user_id) }.to raise_error(Care::Client::Unauthorized)
  end

  it 'raises Error (not retried) on other 4xx and on a body without a segment' do
    stub_request(:get, url).to_return(status: 400, body: '{}')
    expect { client.segment(user_id) }.to raise_error(Care::Client::Error) { |e| expect(e).not_to be_a(Care::Client::Unavailable) }

    stub_request(:get, url).to_return(status: 200, body: '{"status":"ok"}', headers: { 'Content-Type' => 'application/json' })
    expect { client.segment(user_id) }.to raise_error(Care::Client::Error, /unexpected body/)
  end

  it 'raises Unavailable on 5xx and on timeouts' do
    stub_request(:get, url).to_return(status: 503)
    expect { client.segment(user_id) }.to raise_error(Care::Client::Unavailable)

    stub_request(:get, url).to_timeout
    expect { client.segment(user_id) }.to raise_error(Care::Client::Unavailable)
  end

  describe '#queue_config' do
    let(:qurl) { 'https://care.test/api/segments/queue-config' }

    it 'returns settings with classes and the version, and rejects a body without them' do
      payload = { settings: { classes: [{ key: 'vip' }], risk_share: 0.8 }, version: 4, updated_at: nil, updated_by: nil }
      stub_request(:get, qurl).with(headers: { 'Authorization' => 'Bearer svc_key' })
                              .to_return(status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
      expect(client.queue_config).to include('version' => 4)
      expect(client.queue_config['settings']['classes'].first['key']).to eq('vip')

      stub_request(:get, qurl).to_return(status: 200, body: '{"settings":{}}', headers: { 'Content-Type' => 'application/json' })
      expect { client.queue_config }.to raise_error(Care::Client::Error, /unexpected body/)
    end
  end

  describe '#valuable_user_ids' do
    let(:vurl) { 'https://care.test/api/segments/valuable' }

    it 'pages through valuable ids with after_id' do
      first = stub_request(:get, vurl).with(query: { limit: '2' })
                                      .to_return(status: 200, body: { user_ids: ['a' * 24, 'b' * 24], next_after_id: 'b' * 24,
                                                                      total: 3, criteria: {} }.to_json,
                                                 headers: { 'Content-Type' => 'application/json' })
      second = stub_request(:get, vurl).with(query: { limit: '2', after_id: 'b' * 24 })
                                       .to_return(status: 200, body: { user_ids: ['c' * 24], next_after_id: nil, total: 3 }.to_json,
                                                  headers: { 'Content-Type' => 'application/json' })

      page1 = client.valuable_user_ids(limit: 2)
      expect(page1['user_ids']).to eq(['a' * 24, 'b' * 24])
      page2 = client.valuable_user_ids(after_id: page1['next_after_id'], limit: 2)
      expect(page2['user_ids']).to eq(['c' * 24])
      expect(page2['next_after_id']).to be_nil
      expect(first).to have_been_requested.once
      expect(second).to have_been_requested.once
    end

    it 'rejects a body without user_ids' do
      stub_request(:get, vurl).with(query: hash_including({}))
                              .to_return(status: 200, body: '{"status":"ok"}', headers: { 'Content-Type' => 'application/json' })
      expect { client.valuable_user_ids }.to raise_error(Care::Client::Error, /unexpected body/)
    end
  end

  describe '#changed_user_ids' do
    it 'passes since as ISO-8601 UTC and pages by after_id' do
      since = Time.zone.parse('2026-09-07T01:00:00+03:00')
      stub = stub_request(:get, 'https://care.test/api/segments/changed')
             .with(query: { since: '2026-09-06T22:00:00Z', limit: '2', after_id: 'b' * 24 })
             .to_return(status: 200, body: { user_ids: ['c' * 24], next_after_id: nil, total: 3 }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      page = client.changed_user_ids(since: since, after_id: 'b' * 24, limit: 2)
      expect(page['user_ids']).to eq(['c' * 24])
      expect(stub).to have_been_requested.once
    end
  end
end
