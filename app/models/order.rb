class Order < ApplicationRecord
  belongs_to :customer
  has_many :order_items, dependent: :destroy

  STATUSES = %w[pending paid failed].freeze

  validates :reference, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

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

  def assign_reference
    self.reference ||= "DAL-#{SecureRandom.hex(2).upcase}"
  end
end
