import { Controller } from "@hotwired/stimulus"

// Update banner — dismiss + install-steps disclosure.
// Dismiss state lives in localStorage (per-browser, per the local-first principle).
// No server-side dismiss state.
export default class extends Controller {
  static values = { version: String }
  static classes = ["hidden"]

  connect() {
    const dismissed = localStorage.getItem("th_update_dismissed_version")
    if (dismissed === this.versionValue) {
      this.element.classList.add(this.hiddenClass)
    }
  }

  toggle(event) {
    const howto = this.element.querySelector("#th-update-howto")
    const btn = event.currentTarget
    const isHidden = howto.classList.contains(this.hiddenClass)
    if (isHidden) {
      howto.classList.remove(this.hiddenClass)
      btn.setAttribute("aria-expanded", "true")
      btn.textContent = "⌃"
    } else {
      howto.classList.add(this.hiddenClass)
      btn.setAttribute("aria-expanded", "false")
      btn.textContent = "⌄"
    }
  }

  dismiss() {
    localStorage.setItem("th_update_dismissed_version", this.versionValue)
    this.element.classList.add(this.hiddenClass)
  }
}
