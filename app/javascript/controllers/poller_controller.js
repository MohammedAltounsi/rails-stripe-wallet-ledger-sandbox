import { Controller } from "@hotwired/stimulus"

// Reloads the page a few times while something is still settling (e.g. a card
// order waiting on the Stripe webhook). Stops once the server says it's done.
export default class extends Controller {
  static values = {
    done: Boolean,
    interval: { type: Number, default: 1500 },
    max: { type: Number, default: 8 }
  }

  connect() {
    const key = "poll:" + location.pathname
    if (this.doneValue) { sessionStorage.removeItem(key); return }

    const n = parseInt(sessionStorage.getItem(key) || "0", 10)
    if (n >= this.maxValue) return
    sessionStorage.setItem(key, n + 1)
    this.timer = setTimeout(() => location.reload(), this.intervalValue)
  }

  disconnect() { clearTimeout(this.timer) }
}
