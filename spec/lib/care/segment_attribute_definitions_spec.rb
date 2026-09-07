require 'rails_helper'

describe Care::SegmentAttributeDefinitions do
  let(:account) { create(:account) }
  let(:defs) { account.custom_attribute_definitions.with_attribute_model('contact_attribute').where("attribute_key LIKE 'segment_%'") }

  it 'creates the six contact attribute definitions with the right types' do
    result = described_class.ensure!(account)

    expect(result[:created]).to match_array(%w[segment_label segment_role segment_weight segment_tier_90d segment_priority
                                               segment_synced_at])
    expect(result[:updated]).to eq([])
    expect(defs.count).to eq(6)
    expect(defs.find_by(attribute_key: 'segment_weight')).to have_attributes(attribute_display_type: 'list')
    expect(defs.find_by(attribute_key: 'segment_weight').attribute_values).to include('Mega Whale', 'No Purchases')
    expect(defs.find_by(attribute_key: 'segment_priority')).to have_attributes(attribute_display_type: 'number')
    expect(defs.find_by(attribute_key: 'segment_synced_at')).to have_attributes(attribute_display_type: 'date')
  end

  it 'marks the technical attributes as hidden for the dashboard' do
    described_class.ensure!(account)

    expect(defs.find_by(attribute_key: 'segment_priority').attribute_description).to start_with('[hidden] ')
    expect(defs.find_by(attribute_key: 'segment_synced_at').attribute_description).to start_with('[hidden] ')
    expect(defs.find_by(attribute_key: 'segment_label').attribute_description).not_to start_with('[hidden]')
  end

  it 'is idempotent' do
    described_class.ensure!(account)

    expect(described_class.ensure!(account)).to eq(created: [], updated: [])
    expect(defs.count).to eq(6)
  end

  it 'updates only the description of an existing definition when it differs' do
    described_class.ensure!(account)
    definition = defs.find_by(attribute_key: 'segment_priority')
    definition.update!(attribute_description: 'старое описание без пометки', attribute_display_name: 'Custom name')

    result = described_class.ensure!(account)

    expect(result).to eq(created: [], updated: ['segment_priority'])
    definition.reload
    expect(definition.attribute_description).to start_with('[hidden] ')
    expect(definition.attribute_display_name).to eq('Custom name')
  end

  it 'does not rename or retype an existing definition of the same key' do
    account.custom_attribute_definitions.create!(attribute_model: 'contact_attribute', attribute_key: 'segment_label',
                                                 attribute_display_name: 'Custom', attribute_display_type: 'text')
    result = described_class.ensure!(account)

    expect(result[:created]).not_to include('segment_label')
    expect(result[:updated]).to include('segment_label') # описание подтянулось
    expect(account.custom_attribute_definitions.find_by(attribute_key: 'segment_label').attribute_display_name).to eq('Custom')
  end
end
