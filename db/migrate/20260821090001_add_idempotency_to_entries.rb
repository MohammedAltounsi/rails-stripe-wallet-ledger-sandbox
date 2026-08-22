class AddIdempotencyToEntries < ActiveRecord::Migration[8.1]
  def change
    # A caller-supplied key that names one intended money movement.
    # The UNIQUE index is the real guard: the database itself refuses a second
    # entry with the same key, even under a race. NULLs are allowed and don't
    # collide, so entries without a key are unaffected.
    add_column :entries, :idempotency_key, :string
    add_index  :entries, :idempotency_key, unique: true
  end
end
