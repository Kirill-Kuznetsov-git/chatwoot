module ManualEscalation
  extend ActiveSupport::Concern

  included do
    attr_accessor :manual_escalation_release_requested

    # Runs before tag persistence as well as status callbacks. The row lock is
    # held by ActiveRecord's save transaction, serializing labels and resolution.
    before_save :protect_manual_escalation, prepend: true
  end

  def manual_escalation_enabled?
    return false unless ENV.fetch('MANUAL_ESCALATION_ACCOUNT_IDS', '').split(',').map(&:strip).include?(account_id.to_s)

    inbox_ids = ENV.fetch('MANUAL_ESCALATION_INBOX_IDS', '').split(',').map(&:strip).reject(&:blank?)
    inbox_ids.empty? || inbox_ids.include?(inbox_id.to_s)
  end

  def manual_escalation_link_key
    ENV.fetch('MANUAL_ESCALATION_LINK_KEY', '').strip.presence || 'slack_thread_link'
  end

  def manual_escalation_label
    ENV.fetch('MANUAL_ESCALATION_LABEL', '').strip.downcase.presence || 'escalated'
  end

  def manually_escalated?
    return false unless manual_escalation_enabled?

    attributes = self.class.uncached { self.class.where(id: id).pick(:custom_attributes) } if persisted?
    attributes&.[]('manual_escalation_hold') == true || manual_escalation_tagged?
  end

  def manual_escalation_internal_keys
    [manual_escalation_link_key, 'manual_escalation_hold']
  end

  def manual_escalation_tagged?
    label = manual_escalation_label
    # A queued request can have cached the absence of this tag before another
    # connection commits it. Recheck the database after taking the row lock.
    self.class.uncached { labels.exists?(['LOWER(tags.name) = ?', label]) }
  end

  def public_custom_attributes
    custom_attributes&.except(*manual_escalation_internal_keys)
  end

  def with_manual_escalation_lock(&)
    manual_escalation_enabled? ? with_lock(&) : yield
  end

  def replace_public_custom_attributes!(attributes)
    with_lock do
      internal_attributes = (custom_attributes || {}).slice(*manual_escalation_internal_keys)
      update!(custom_attributes: (attributes || {}).except(*manual_escalation_internal_keys).merge(internal_attributes))
    end
  end

  private

  def protect_manual_escalation
    return unless manual_escalation_enabled? || customer_escalation_link_update?

    persisted = self.class.lock.find(id) if persisted?
    refresh_unchanged_custom_attributes(persisted)
    protect_customer_escalation_link(persisted) if customer_escalation_link_update?
    return unless manual_escalation_enabled?

    sync_manual_escalation_hold(persisted)
    restore_manual_escalation_status(persisted)
  end

  def refresh_unchanged_custom_attributes(persisted)
    return unless persisted && !will_save_change_to_custom_attributes?

    self.custom_attributes = persisted.custom_attributes
  end

  def sync_manual_escalation_hold(persisted)
    tagged = pending_manual_escalation_tag?(persisted)
    return unless previously_held_manual_escalation?(persisted) || tagged

    release = manual_escalation_release_allowed?(tagged)
    self.custom_attributes = (custom_attributes || {}).merge('manual_escalation_hold' => !release)
    self.status = :open if pending? && !release
  end

  def previously_held_manual_escalation?(persisted)
    persisted&.custom_attributes&.[]('manual_escalation_hold') == true || persisted&.manual_escalation_tagged?
  end

  def pending_manual_escalation_tag?(persisted)
    return persisted&.manual_escalation_tagged? unless label_list_changed?

    label_list.any? { |label| label.downcase == manual_escalation_label }
  end

  def manual_escalation_release_allowed?(tagged)
    manual_escalation_release_requested && human_operator_escalation_action? && pending? && !tagged
  end

  def restore_manual_escalation_status(persisted)
    return unless persisted && (automatic_escalation_transition? || automatic_manual_escalation_reopening?(persisted))
    return unless persisted.manually_escalated? || pending_manual_escalation_tag?(persisted)

    self.status = persisted.status
    self.snoozed_until = persisted.snoozed_until
  end

  def automatic_escalation_transition?
    will_save_change_to_status? && (resolved? || pending?) && !human_escalation_action?
  end

  def automatic_manual_escalation_reopening?(persisted)
    will_save_change_to_status? && open? && persisted.resolved? && Current.user.is_a?(AgentBot)
  end

  def customer_escalation_link_update?
    Current.contact.present? && will_save_change_to_custom_attributes?
  end

  def human_escalation_action?
    return true if Current.contact.present? || Current.user.is_a?(Contact)

    human_operator_escalation_action?
  end

  def human_operator_escalation_action?
    Current.user.is_a?(User) && !Current.executed_by.is_a?(AutomationRule)
  end

  def protect_customer_escalation_link(persisted)
    return unless will_save_change_to_custom_attributes?

    self.custom_attributes = public_custom_attributes || {}
    custom_attributes.merge!((persisted&.custom_attributes || {}).slice(*manual_escalation_internal_keys))
  end
end
