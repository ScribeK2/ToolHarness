import { Controller } from "@hotwired/stimulus"

// Hides the update banner for the specified version, persisting via localStorage.
// Per the local-first / per-browser-prefs principle: no server-side dismiss state.
export default class extends Controller {
  static values = { version: String }
  static classes = ["hidden"]

  connect() {
    const dismissed = localStorage.getItem("th_update_dismissed_version")
    if (dismissed === this.versionValue) {
      this.element.classList.add(this.hiddenClass)
    }
  }

  dismiss() {
    localStorage.setItem("th_update_dismissed_version", this.versionValue)
    this.element.classList.add(this.hiddenClass)
  }
}
