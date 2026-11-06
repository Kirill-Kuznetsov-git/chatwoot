require 'rails_helper'

RSpec.describe Conversations::FilterService do
  subject(:result) { described_class.new({ payload: payload, page: 1 }, agent, account).perform }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:whale) do
    contact = create(:contact, account: account, custom_attributes: { segment_weight: 'Whale', segment_role: 'Seller' })
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent, status: :open)
  end
  let!(:fish) do
    contact = create(:contact, account: account, custom_attributes: { segment_weight: 'Small Fish', segment_role: 'Buyer' })
    create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending)
  end
  let!(:missing) { create(:conversation, account: account, inbox: inbox) }
  let(:condition) do
    { attribute_key: 'care_segment_weight', filter_operator: 'equal_to', values: ['Whale'], query_operator: nil }.with_indifferent_access
  end
  let(:payload) { [condition] }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'filters the contact segment without duplicating conversations or changing assignment counts' do
    whale.update!(custom_attributes: { segment_weight: 'Small Fish' })
    expect(result[:conversations].pluck(:id)).to eq([whale.id])
    expect(result[:count]).to include(all_count: 1, mine_count: 1, assigned_count: 1, unassigned_count: 0)
  end

  it 'includes unclassified contacts in not equal to' do
    condition[:filter_operator] = 'not_equal_to'
    expect(result[:conversations].pluck(:id)).to contain_exactly(fish.id, missing.id)
  end

  it 'combines role with weight using AND' do
    condition[:query_operator] = 'AND'
    payload << { attribute_key: 'care_segment_role', filter_operator: 'equal_to', values: ['Buyer'] }.with_indifferent_access
    expect(result[:count][:all_count]).to eq(0)
  end

  it 'keeps inbox and account boundaries when combined using OR' do
    hidden = create(:inbox, account: account)
    create(:conversation, account: account, inbox: hidden, contact: whale.contact)
    create(:conversation, status: :pending)
    condition[:query_operator] = 'OR'
    payload << { attribute_key: 'status', filter_operator: 'equal_to', values: ['pending'] }.with_indifferent_access
    expect(result[:conversations].pluck(:id)).to contain_exactly(whale.id, fish.id)
  end

  it 'supports multiple weights and multiple conversations of the same contact' do
    another = create(:conversation, account: account, inbox: inbox, contact: whale.contact)
    condition[:values] = ['Whale', 'Small Fish']
    expect(result[:conversations].pluck(:id)).to contain_exactly(whale.id, another.id, fish.id)
    expect(result[:count][:all_count]).to eq(3)
  end

  it 'rejects unknown values and SQL-like payloads' do
    [[], ['Whale', "x') OR TRUE --"], ['whale'], 'Whale', [nil], [{}]].each do |values|
      condition[:values] = values
      expect { described_class.new({ payload: payload }, agent, account).perform }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::CustomFilter::InvalidValue') })
    end
  end

  it 'rejects unsupported segment operators' do
    condition[:filter_operator] = 'contains'
    expect { result }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::CustomFilter::InvalidOperator') })
  end
end
