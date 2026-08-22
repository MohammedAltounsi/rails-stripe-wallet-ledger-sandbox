class ReconciliationController < ApplicationController
  def show
    @result = ReconciliationService.run
  end
end
