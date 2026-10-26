module ManualEscalationDetails
  extend ActiveSupport::Concern

  included do
    before_validation :validate_manual_escalation_details
  end

  private

  def validate_manual_escalation_details
    return unless will_save_change_to_custom_attributes?
    return if Current.contact.present? || Current.user.is_a?(Contact)

    details = ManualEscalations::Details.new(self)
    details.normalize_attributes!
    return unless details.changed?

    details.validate(custom_attributes || {}).each { |message| errors.add(:custom_attributes, message) }
  end
end
