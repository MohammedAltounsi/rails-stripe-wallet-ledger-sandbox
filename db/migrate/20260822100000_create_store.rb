class CreateStore < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :name, null: false
      t.string :ref,  null: false          # slug; the wallet ledger account is "wallet:<ref>"
      t.string :email
      t.timestamps
    end
    add_index :customers, :ref, unique: true

    create_table :products do |t|
      t.string  :name,        null: false
      t.string  :tagline
      t.text    :description
      t.integer :price_cents, null: false   # halalas — never a float
      t.string  :emoji
      t.string  :roast                       # light / medium / dark
      t.boolean :active,      null: false, default: true
      t.integer :position,    null: false, default: 0
      t.timestamps
    end

    create_table :orders do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :reference,   null: false   # human order number, e.g. DAL-4F9C
      t.string  :status,      null: false, default: "pending"  # pending / paid / failed
      t.string  :payment_method              # wallet / card
      t.integer :total_cents, null: false, default: 0
      t.string  :stripe_payment_intent_id
      t.timestamps
    end
    add_index :orders, :reference, unique: true
    add_index :orders, :stripe_payment_intent_id

    create_table :order_items do |t|
      t.references :order,   null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity,         null: false, default: 1
      t.integer :unit_price_cents, null: false   # price captured at purchase time
      t.timestamps
    end
  end
end
