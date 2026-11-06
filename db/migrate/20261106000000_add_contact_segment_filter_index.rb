class AddContactSegmentFilterIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    with_index_timeouts do
      add_index :contacts, "account_id, (custom_attributes ->> 'segment_weight'), (custom_attributes ->> 'segment_role'), id",
                name: 'index_contacts_on_care_segments',
                where: "custom_attributes ? 'segment_weight' OR custom_attributes ? 'segment_role'",
                algorithm: :concurrently
    end
  end

  def down
    with_index_timeouts { remove_index :contacts, name: 'index_contacts_on_care_segments', algorithm: :concurrently }
  end

  private

  def with_index_timeouts
    statement_timeout = connection.select_value('SHOW statement_timeout')
    lock_timeout = connection.select_value('SHOW lock_timeout')
    execute "SET statement_timeout = '15min'"
    execute "SET lock_timeout = '2s'"
    yield
  ensure
    execute "SET statement_timeout = #{connection.quote(statement_timeout)}"
    execute "SET lock_timeout = #{connection.quote(lock_timeout)}"
  end
end
