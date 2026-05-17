import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    this.onKey = (e) => { if (e.key === "Escape") this.dismiss() }
    document.addEventListener("keydown", this.onKey)
    if (this.timeoutValue > 0) {
      this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.remove()
  }
}
