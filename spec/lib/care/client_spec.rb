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
end
