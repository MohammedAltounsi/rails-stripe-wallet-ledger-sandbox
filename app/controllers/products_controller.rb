class ProductsController < ApplicationController
  def index
    @sections = Product.by_category   # [[category, [products]], ...] in menu order
  end

  def show
    @product = Product.available.find(params[:id])
  end
end
