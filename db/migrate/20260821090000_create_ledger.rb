class CreateLedger < ActiveRecord::Migration[8.1]
  def change
    # An account is anything money can sit in or flow through:
    # a customer's wallet, your Stripe cash account, a revenue account.
    create_table :accounts do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :accounts, :name, unique: true

    # An entry is one whole money movement (a "transaction" in the real sense):
    # e.g. "customer topped up 50 SAR". It groups the postings below.
    create_table :entries do |t|
      t.string :memo, null: false
      t.timestamps
    end

    # A posting is ONE line inside an entry: how much moved into/out of ONE account.
    # amount_cents is in MINOR UNITS (halalas): 50.00 SAR = 5000. Always an integer,
    # never a float. + means money into the account, - means out.
    # The rule that makes it double-entry: every posting in an entry must sum to ZERO.
    create_table :postings do |t|
      t.references :entry,   null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.timestamps
    end
  end
end
