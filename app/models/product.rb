class Product < ApplicationRecord
  # Menu section order, top to bottom.
  CATEGORIES = ["Hot Coffee", "Iced Coffee", "Signature", "Tea & More"].freeze

  scope :available, -> { where(active: true).order(:position, :id) }

  def self.by_category
    available.group_by(&:category).sort_by { |cat, _| CATEGORIES.index(cat) || 99 }
  end

  def customizable_temperature?
    temperature == "both"
  end

  def default_temperature
    temperature == "iced" ? "Iced" : "Hot"
  end
end
