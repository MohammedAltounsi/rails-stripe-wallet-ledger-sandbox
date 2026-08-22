import { Controller } from "@hotwired/stimulus"

// Copy a value to the clipboard and flash a confirmation on the button.
// Replaces an inline onclick handler so a strict CSP (no unsafe-inline) holds.
export default class extends Controller {
  static values = { text: String, done: { type: String, default: "Copied" } }

  copy(event) {
    const btn = event.currentTarget
    navigator.clipboard.writeText(this.textValue).then(() => {
      const original = btn.textContent
      btn.textContent = this.doneValue
      setTimeout(() => { btn.textContent = original }, 1200)
    })
  }
}
