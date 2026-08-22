import { Controller } from "@hotwired/stimulus"

// Live drink customizer: recomputes the price as the shopper changes size,
// shots, temperature, milk, and syrup, and mirrors the choice into the visual.
export default class extends Controller {
  static values = {
    base: Number,             // Tall base price, halalas
    sizeDeltas: Object,       // { Tall:0, Grande:300, Venti:600 }
    shotPrice: Number         // per extra shot
  }
  static targets = ["price", "cup"]

  connect() { this.update() }

  update() {
    const size  = this.field("size")
    const shots = parseInt(this.field("shots") || "0", 10)
    const delta = this.sizeDeltasValue[size] ?? 0
    const cents = this.baseValue + delta + shots * this.shotPriceValue
    if (this.hasPriceTarget) this.priceTarget.textContent = "SAR " + (cents / 100).toFixed(2)

    // Iced ⇒ swap the cup visual state (class toggle the CSS reacts to).
    if (this.hasCupTarget) {
      const iced = this.field("temperature") === "Iced"
      this.cupTarget.classList.toggle("is-iced", iced)
    }
  }

  field(name) {
    const checked = this.element.querySelector(`input[name="${name}"]:checked`)
    if (checked) return checked.value
    const el = this.element.querySelector(`[name="${name}"]`)
    return el ? el.value : null
  }
}
