# Be sure to restart your server when you modify this file.
# Application-wide Content Security Policy.
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# Allowlist reflects exactly what the app loads:
#   - Stripe.js + its frames (Payment Element)
#   - Google Fonts (stylesheet on fonts.googleapis.com, files on fonts.gstatic.com)
#   - product photos hotlinked from images.pexels.com
# Inline <script> (the importmap + module entry) is allowed via a per-request
# nonce, NOT 'unsafe-inline', so injected scripts still can't run. Inline styles
# are pervasive (gradients, gift cards) and can't take a nonce, so style keeps
# 'unsafe_inline'; that only affects styling, not script execution.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.form_action     :self
    policy.object_src      :none
    policy.frame_ancestors :none
    policy.img_src         :self, :data, "https://images.pexels.com"
    policy.font_src        :self, :data, "https://fonts.gstatic.com"
    policy.style_src       :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.script_src      :self, "https://js.stripe.com"
    policy.frame_src       "https://js.stripe.com", "https://hooks.stripe.com"
    policy.connect_src     :self, "https://api.stripe.com"
  end

  # Nonce the inline importmap/module scripts so they run without 'unsafe-inline'.
  # A fresh per-request random (not session.id, which is blank before a session
  # exists and would emit an empty, script-breaking nonce).
  config.content_security_policy_nonce_generator  = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives  = %w[script-src]
end
