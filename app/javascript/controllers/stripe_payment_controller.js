import { Controller } from "@hotwired/stimulus"

// Mounts a real Stripe Payment Element and confirms the PaymentIntent.
// The server credits the wallet / marks the order paid only on the webhook —
// this controller just captures the card and reports success to the UI.
export default class extends Controller {
  static values = {
    publishableKey: String,
    clientSecret: String,
    returnUrl: String
  }
  static targets = ["submit", "error", "label"]

  connect() {
    if (typeof Stripe === "undefined") { return } // js.stripe.com not loaded yet
    this.stripe = Stripe(this.publishableKeyValue)

    const appearance = {
      theme: "stripe",
      variables: {
        colorPrimary: "#9a6d1e",
        colorBackground: "#ffffff",
        colorText: "#2a201a",
        colorTextSecondary: "#6b6154",
        fontFamily: "Hanken Grotesk, system-ui, sans-serif",
        borderRadius: "12px",
        spacingUnit: "4px"
      }
    }
    this.elements = this.stripe.elements({ clientSecret: this.clientSecretValue, appearance })
    this.elements.create("payment", { layout: "tabs" }).mount("#payment-element")
  }

  async submit(event) {
    event.preventDefault()
    this.busy(true)

    const { error } = await this.stripe.confirmPayment({
      elements: this.elements,
      confirmParams: { return_url: this.returnUrlValue },
      redirect: "if_required"
    })

    if (error) {
      // Card declined, incomplete, etc. Stay on the page and show why.
      this.showError(error.message || "Payment could not be completed.")
      this.busy(false)
    } else {
      // Card cleared inline (no 3-D Secure redirect). Give the webhook a beat to
      // land, then move on — the server is the source of truth for the balance.
      setTimeout(() => window.location.assign(this.returnUrlValue), 1200)
    }
  }

  busy(on) {
    if (!this.hasSubmitTarget) return
    this.submitTarget.disabled = on
    if (this.hasLabelTarget) this.labelTarget.textContent = on ? "Processing…" : this.labelTarget.dataset.idle
  }

  showError(msg) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = msg
    this.errorTarget.classList.remove("hidden")
  }
}
