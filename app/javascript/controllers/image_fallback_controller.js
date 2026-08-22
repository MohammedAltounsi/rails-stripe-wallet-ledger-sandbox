import { Controller } from "@hotwired/stimulus"

// When a product photo fails to load, remove it so the SVG cup fallback shows
// through (or hide a wrapper). Replaces an inline onerror handler for CSP.
// data-image-fallback-mode-value: "remove" (default) or "hide-closest".
// data-image-fallback-target-value: CSS selector for "hide-closest".
export default class extends Controller {
  static values = { mode: { type: String, default: "remove" }, target: String }

  connect() {
    // Catch the case where the image already failed before Stimulus connected.
    if (this.element.complete && this.element.naturalWidth === 0) this.handle()
  }

  handle() {
    if (this.modeValue === "hide-closest" && this.targetValue) {
      this.element.closest(this.targetValue)?.style.setProperty("display", "none")
    } else {
      this.element.remove()
    }
  }
}
