class SessionsController < ApplicationController
  # Demo-only: switch which customer you're shopping as.
  def switch
    customer = Customer.find_by!(ref: params[:ref])
    session[:customer_id] = customer.id
    redirect_back fallback_location: root_path, notice: "Now shopping as #{customer.name}."
  end
end
