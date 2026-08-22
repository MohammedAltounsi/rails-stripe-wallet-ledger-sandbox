require "test_helper"

# Guards the wallet-spend path in CheckoutController#pay_with_wallet: the
# balance check + debit run inside one locked transaction, and an insufficient
# balance must roll back cleanly, writing no order and no postings.
class WalletCheckoutTest < ActionDispatch::IntegrationTest
  setup do
    @customer = Customer.create!(name: "Test", ref: "test-#{SecureRandom.hex(3)}", email: "t@example.com")
    @product  = Product.create!(name: "Test Latte #{SecureRandom.hex(2)}", category: "Hot Coffee",
                                price_cents: 1800, temperature: "both", active: true)
    post switch_customer_path(@customer.ref)   # shop as this customer for the rest of the test
  end

  def add_one_to_cart
    post cart_items_path, params: { product_id: @product.id, quantity: 1,
                                    size: "Tall", temperature: "Hot", milk: "Whole", syrup: "None", shots: "0" }
  end

  def fund_wallet(cents)
    Ledger.post!("fund",
      [[Ledger.account(Ledger::CASH_ACCOUNT), -cents], [@customer.wallet_account, +cents]],
      key: "fund-#{@customer.ref}")
  end

  test "enough balance: debits exactly the total and marks the order paid" do
    fund_wallet(5000)
    add_one_to_cart
    assert_difference -> { Order.where(status: "paid").count }, 1 do
      post checkout_path, params: { pay: "wallet", email: "t@example.com" }
    end
    assert_equal 5000 - 1800, @customer.wallet_balance_cents
  end

  test "checkout token is unique: a duplicate order for the same token collides" do
    fund_wallet(10000)
    add_one_to_cart
    get checkout_path                                  # sets session[:checkout_token]
    post checkout_path, params: { pay: "wallet", email: "t@example.com" }
    first = Order.order(:id).last
    assert first.checkout_token.present?, "order should carry the checkout token"

    # A second paid order reusing the same token is what a double-tap would do;
    # the unique index rejects it, so the shopper can't be charged twice.
    assert_raises(ActiveRecord::RecordNotUnique) do
      Order.create!(customer: @customer, payment_method: "wallet", total_cents: 1800,
                    status: "pending", reference: "DAL-DUPTOKEN", checkout_token: first.checkout_token)
    end
  end

  test "insufficient balance: rejected, and no order or posting is written" do
    add_one_to_cart   # balance is 0
    assert_no_difference -> { Order.count } do
      assert_no_difference -> { Posting.count } do
        post checkout_path, params: { pay: "wallet", email: "t@example.com" }
      end
    end
    assert_redirected_to checkout_path
    assert_equal 0, @customer.wallet_balance_cents
  end
end
