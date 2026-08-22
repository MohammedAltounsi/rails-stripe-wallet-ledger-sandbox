class Order < ApplicationRecord
  belongs_to :customer
  has_many :order_items, dependent: :destroy

  STATUSES = %w[pending paid failed].freeze

  validates :reference, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate  :total_matches_line_items, on: :create

  before_validation :assign_reference, on: :create

  def paid?
    status == "paid"
  end

  def pending?
    status == "pending"
  end

  # Sum of line items — the truth the total_cents column must match.
  def computed_total_cents
    order_items.sum { |i| i.quantity * i.unit_price_cents }
  end

  private

  # ~2.8e12 space (36^8), so a UNIQUE-index collision that would 500 a real
  # payment is astronomically unlikely (was hex(2) = only 65,536 values).
  def assign_reference
    self.reference ||= "DAL-#{SecureRandom.alphanumeric(8).upcase}"
  end

  # Defense-in-depth: the stored total must equal the sum of its line items.
  # Pricing is fully server-side today, so this only backstops a future
  # promo/import/admin path that might set a total by hand.
  def total_matches_line_items
    return if order_items.empty?
    errors.add(:total_cents, "must equal the sum of line items") unless total_cents == computed_total_cents
  end
end
