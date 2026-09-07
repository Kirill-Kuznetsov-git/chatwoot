# == Schema Information
#
# Table name: care_sla_trackers
#
#  id                    :bigint           not null, primary key
#  active                :boolean          default(TRUE), not null
#  class_key             :string           not null
#  class_name            :string           not null
#  closed_at             :datetime
#  closed_reason         :string
#  config_version        :integer          default(0), not null
#  first_response_at     :datetime
#  fr_breached_at        :datetime
#  fr_due_at             :datetime
#  fr_state              :string           default("none"), not null
#  labels_applied        :jsonb            not null
#  nr_anchor_at          :datetime
#  nr_breached_anchor_at :datetime
#  nr_breached_at        :datetime
#  nr_due_at             :datetime
#  nr_state              :string           default("none"), not null
#  priority_applied      :string
#  priority_manual       :boolean          default(FALSE), not null
#  reopened_at           :datetime
#  res_breached_at       :datetime
#  res_due_at            :datetime
#  res_state             :string           default("none"), not null
#  resolved_at           :datetime
#  started_at            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  contact_id            :bigint           not null
#  conversation_id       :bigint           not null
#
# Indexes
#
#  index_care_sla_trackers_on_account_id_and_active      (account_id,active)
#  index_care_sla_trackers_on_account_id_and_started_at  (account_id,started_at)
#  index_care_sla_trackers_on_contact_id                 (contact_id)
#  index_care_sla_trackers_on_conversation_id            (conversation_id) UNIQUE
#

# Диалог ценного клиента в очереди людей (SCC-102). Одна запись на диалог: якоря времени (передача
# человеку, повторное открытие), сроки и состояния трёх таймеров (fr — первый ответ человека,
# nr — ответ на сообщение клиента, res — решение) и то, что мы сами выставили диалогу (приоритет,
# лейблы), чтобы уметь это снять при смене конфига или сегмента, не трогая ручные правки операторов.
# Состояния каждый тик пересчитываются заново — см. Care::Sla::Evaluator и Care::Sla::Reconciler.
class Care::SlaTracker < ApplicationRecord
  self.table_name = 'care_sla_trackers'

  STATES = %w[none ok at_risk breached met].freeze
  CLOSED_REASONS = %w[resolved untracked].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :contact

  validates :class_key, :class_name, :started_at, presence: true
  validates :fr_state, :nr_state, :res_state, inclusion: { in: STATES }
  validates :closed_reason, inclusion: { in: CLOSED_REASONS }, allow_nil: true

  scope :active, -> { where(active: true) }

  def states
    [fr_state, nr_state, res_state]
  end

  def breached?
    states.include?('breached')
  end

  def at_risk?
    states.include?('at_risk')
  end
end
