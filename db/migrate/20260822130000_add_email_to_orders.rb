class AddEmailToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :email, :string
  end
end
