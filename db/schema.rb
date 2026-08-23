# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_23_060000) do
  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_accounts_on_name", unique: true
  end

  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.string "ref", null: false
    t.datetime "updated_at", null: false
    t.index ["ref"], name: "index_customers_on_ref", unique: true
  end

  create_table "entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.string "memo", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_entries_on_idempotency_key", unique: true
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "milk"
    t.integer "order_id", null: false
    t.integer "product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "shots", default: 0, null: false
    t.string "size"
    t.string "syrup"
    t.string "temperature"
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "checkout_token"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.string "email"
    t.string "payment_method"
    t.string "pickup_store"
    t.string "pickup_time"
    t.string "reference", null: false
    t.string "status", default: "pending", null: false
    t.string "stripe_payment_intent_id"
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["checkout_token"], name: "index_orders_on_checkout_token", unique: true
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["reference"], name: "index_orders_on_reference", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_orders_on_stripe_payment_intent_id"
  end

  create_table "postings", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.integer "entry_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_postings_on_account_id"
    t.index ["entry_id"], name: "index_postings_on_entry_id"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "category"
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "description_ar"
    t.string "emoji"
    t.string "image_url"
    t.string "name", null: false
    t.string "name_ar"
    t.integer "position", default: 0, null: false
    t.integer "price_cents", null: false
    t.string "roast"
    t.string "tagline"
    t.string "tagline_ar"
    t.string "temperature", default: "both", null: false
    t.datetime "updated_at", null: false
  end

  create_table "stripe_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.text "payload"
    t.datetime "processed_at"
    t.string "status", default: "received", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_stripe_events_on_event_id", unique: true
  end

  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "customers"
  add_foreign_key "postings", "accounts"
  add_foreign_key "postings", "entries"
end
