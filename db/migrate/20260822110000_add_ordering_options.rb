class AddOrderingOptions < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :category,    :string
    add_column :products, :temperature, :string, default: "both", null: false  # hot / iced / both
    add_column :products, :color,       :string                                  # drink tone for the visual

    add_column :order_items, :size,        :string
    add_column :order_items, :temperature, :string
    add_column :order_items, :milk,        :string
    add_column :order_items, :shots,       :integer, default: 0, null: false
    add_column :order_items, :syrup,       :string

    add_column :orders, :pickup_store, :string
    add_column :orders, :pickup_time,  :string
  end
end
