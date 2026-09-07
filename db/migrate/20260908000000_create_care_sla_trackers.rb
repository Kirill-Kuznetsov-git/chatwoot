class CreateCareSlaTrackers < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :care_sla_trackers do |t|
      t.references :account, null: false, index: false
      t.references :conversation, null: false, index: { unique: true }
      t.references :contact, null: false, index: true
      t.string :class_key, null: false
      t.string :class_name, null: false
      t.integer :config_version, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :reopened_at
      t.datetime :first_response_at
      t.datetime :resolved_at
      t.datetime :nr_anchor_at
      t.datetime :fr_due_at
      t.datetime :nr_due_at
      t.datetime :res_due_at
      t.string :fr_state, null: false, default: 'none'
      t.string :nr_state, null: false, default: 'none'
      t.string :res_state, null: false, default: 'none'
      t.datetime :fr_breached_at
      t.datetime :nr_breached_at
      t.datetime :nr_breached_anchor_at
      t.datetime :res_breached_at
      t.string :priority_applied
      t.boolean :priority_manual, null: false, default: false
      t.jsonb :labels_applied, null: false, default: []
      t.boolean :active, null: false, default: true
      t.string :closed_reason
      t.datetime :closed_at

      t.timestamps
    end

    add_index :care_sla_trackers, [:account_id, :active]
    add_index :care_sla_trackers, [:account_id, :started_at]
  end
end
