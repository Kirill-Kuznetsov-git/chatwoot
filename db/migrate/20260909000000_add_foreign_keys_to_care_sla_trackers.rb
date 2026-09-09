# Диалог, контакт или аккаунт могут быть удалены (удаление контакта из карточки, чистка старых
# диалогов, удаление аккаунта). Без внешних ключей SLA-трекер оставался сиротой, и ежеминутный
# пересчёт падал на нём каждую минуту. Каскад в БД решает это, не трогая upstream-модели.
class AddForeignKeysToCareSlaTrackers < ActiveRecord::Migration[7.1]
  def up
    execute 'DELETE FROM care_sla_trackers WHERE conversation_id NOT IN (SELECT id FROM conversations)'
    execute 'DELETE FROM care_sla_trackers WHERE contact_id NOT IN (SELECT id FROM contacts)'
    execute 'DELETE FROM care_sla_trackers WHERE account_id NOT IN (SELECT id FROM accounts)'
    add_foreign_key :care_sla_trackers, :conversations, on_delete: :cascade, validate: false
    add_foreign_key :care_sla_trackers, :contacts, on_delete: :cascade, validate: false
    add_foreign_key :care_sla_trackers, :accounts, on_delete: :cascade, validate: false
  end

  def down
    remove_foreign_key :care_sla_trackers, :conversations
    remove_foreign_key :care_sla_trackers, :contacts
    remove_foreign_key :care_sla_trackers, :accounts
  end
end
