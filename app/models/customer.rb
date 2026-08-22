class Customer < ApplicationRecord
  has_many :orders, dependent: :destroy

  validates :ref, presence: true, uniqueness: true

  # A customer's stored-value wallet is a ledger account named "wallet:<ref>".
  # The balance lives in the ledger and is derived by summing postings — never
  # stored on this row, so it can't drift out of sync with the money.
  def wallet_account
    Account.find_or_create_by!(name: "wallet:#{ref}")
  end

  def wallet_balance_cents
    Account.find_by(name: "wallet:#{ref}")&.balance_cents || 0
  end
end
