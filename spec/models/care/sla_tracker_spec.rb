require 'rails_helper'

describe Care::SlaTracker do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, identifier: 'a1' * 12) }
  let(:conversation) { create(:conversation, account: account, contact: contact, status: :open) }
  let!(:tracker) do
    described_class.create!(account: account, conversation: conversation, contact: contact, class_key: 'vip', class_name: 'VIP',
                            started_at: 1.hour.ago)
  end

  it 'goes away with its conversation, so the minute tick never meets an orphan' do
    conversation.destroy!
    expect(described_class.where(id: tracker.id)).to be_empty
  end

  it 'goes away with its contact' do
    contact.destroy!
    expect(described_class.where(id: tracker.id)).to be_empty
  end

  it 'keeps one tracker per conversation' do
    duplicate = described_class.new(account: account, conversation: conversation, contact: contact, class_key: 'big',
                                    class_name: 'Big', started_at: Time.current)
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
