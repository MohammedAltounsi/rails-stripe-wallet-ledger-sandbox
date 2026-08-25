class CreateReconciliationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_runs do |t|
      t.string  :status,           null: false            # clean | drift | unreachable
      t.integer :stripe_count,     null: false, default: 0
      t.integer :matched,          null: false, default: 0
      t.integer :missing_count,    null: false, default: 0
      t.integer :mismatched_count, null: false, default: 0
      t.integer :orphan_count,     null: false, default: 0
      t.integer :global_sum_cents, null: false, default: 0
      t.timestamps
    end
  end
end
