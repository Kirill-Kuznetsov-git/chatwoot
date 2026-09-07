require 'rails_helper'

describe Care::SegmentAttributeDefinitions do
  let(:account) { create(:account) }

  let(:defs) { account.custom_attribute_definitions.with_attribute_model('contact_attribute').where("attribute_key LIKE 'segment_%'") }

  it 'creates the six contact attribute definitions with the right types' do
    created = described_class.ensure!(account)

    expect(created).to match_array(%w[segment_label segment_role segment_weight segment_tier_90d segment_priority segment_synced_at])
    expect(defs.count).to eq(6)
    expect(defs.find_by(attribute_key: 'segment_weight')).to have_attributes(attribute_display_type: 'list')
    expect(defs.find_by(attribute_key: 'segment_weight').attribute_values).to include('Mega Whale', 'No Purchases')
    expect(defs.find_by(attribute_key: 'segment_priority')).to have_attributes(attribute_display_type: 'number')
    expect(defs.find_by(attribute_key: 'segment_synced_at')).to have_attributes(attribute_display_type: 'date')
  end

  it 'is idempotent' do
    described_class.ensure!(account)

    expect(described_class.ensure!(account)).to eq([])
    expect(defs.count).to eq(6)
  end

  it 'does not touch existing definitions of the same key' do
    account.custom_attribute_definitions.create!(attribute_model: 'contact_attribute', attribute_key: 'segment_label',
                                                 attribute_display_name: 'Custom', attribute_display_type: 'text')
    created = described_class.ensure!(account)
    expect(created).not_to include('segment_label')
    expect(account.custom_attribute_definitions.find_by(attribute_key: 'segment_label').attribute_display_name).to eq('Custom')
  end
end
