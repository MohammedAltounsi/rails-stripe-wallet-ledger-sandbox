class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "Dallah Coffee <receipts@dallah.coffee>")
  helper ApplicationHelper   # so views can use money(...)
  layout "mailer"
end
