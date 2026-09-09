# Индекс по created_at нужен ежедневной уборке пустых сессий (Internal::RemoveStaleContactInboxesService):
# без него выборка «сессии старше N дней» сканирует всю таблицу и не укладывается в statement_timeout воркера.
class AddIndexOnCreatedAtToContactInboxes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :contact_inboxes, :created_at, algorithm: :concurrently, if_not_exists: true
  end
end
