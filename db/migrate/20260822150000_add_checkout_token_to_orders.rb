class AddCheckoutTokenToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :checkout_token, :string
    # One order per checkout token: a double-submit (concurrent double-tap)
    # collides on the unique index instead of creating a second paid order.
    add_index :orders, :checkout_token, unique: true
  end
end
