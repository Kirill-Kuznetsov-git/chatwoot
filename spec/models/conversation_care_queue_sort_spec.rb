require 'rails_helper'

# Порядок живой очереди (SCC-102): важность клиента, внутри неё — кто дольше ждёт ответа.
describe Conversation do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def conversation(priority:, waiting_minutes: nil, created_minutes: 10)
    create(:conversation, account: account, inbox: inbox, status: :open, priority: priority,
                          created_at: created_minutes.minutes.ago).tap do |conv|
      conv.update_columns(waiting_since: waiting_minutes&.minutes&.ago) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it 'ставит важных выше, а внутри важности — того, кто ждёт дольше' do
    urgent_fresh = conversation(priority: :urgent, waiting_minutes: 5)
    urgent_old = conversation(priority: :urgent, waiting_minutes: 300)
    high_old = conversation(priority: :high, waiting_minutes: 600)
    plain = conversation(priority: nil, waiting_minutes: 900)

    expect(account.conversations.open.sort_on_priority_waiting_since(:desc).map(&:id))
      .to eq([urgent_old.id, urgent_fresh.id, high_old.id, plain.id])
  end

  it 'уводит в конец своей группы диалоги, где клиент уже не ждёт ответа' do
    answered = conversation(priority: :urgent, waiting_minutes: nil, created_minutes: 500)
    waiting_short = conversation(priority: :urgent, waiting_minutes: 3)

    expect(account.conversations.open.sort_on_priority_waiting_since(:desc).map(&:id))
      .to eq([waiting_short.id, answered.id])
  end

  it 'при равном ожидании держит порядок поступления' do
    first = conversation(priority: :urgent, waiting_minutes: nil, created_minutes: 90)
    second = conversation(priority: :urgent, waiting_minutes: nil, created_minutes: 30)

    expect(account.conversations.open.sort_on_priority_waiting_since(:desc).map(&:id)).to eq([first.id, second.id])
  end

  it 'доступна списку диалогов под ключом priority_desc_waiting_since_asc' do
    expect(ConversationFinder::SORT_OPTIONS['priority_desc_waiting_since_asc'])
      .to eq(%w[sort_on_priority_waiting_since desc])

    user = create(:user, account: account, role: :administrator)
    create(:inbox_member, user: user, inbox: inbox)
    urgent = conversation(priority: :urgent, waiting_minutes: 200)
    conversation(priority: nil, waiting_minutes: 900)
    Current.account = account

    result = ConversationFinder.new(user, { status: 'open', sort_by: 'priority_desc_waiting_since_asc',
                                            assignee_type: 'all' }).perform
    expect(result[:conversations].first.id).to eq(urgent.id)
  ensure
    Current.account = nil
  end
end
