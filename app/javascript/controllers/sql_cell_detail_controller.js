import { Controller } from "@hotwired/stimulus"

// Keyboard handling inside the SQL cell-detail overlay.
//  - ESC : close overlay (hide via the `hidden` class)
//  - y c : copy the cell's full text value to clipboard
//
// Same pattern as sql_picker_controller / sql_history_controller — owns its
// own keydown listener, bails when the overlay element has the `hidden` class.
export default class extends Controller {
  connect() {
    this.onKeydown = (e) => this.handleKey(e)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  handleKey(e) {
    if (this.element.classList.contains("hidden")) return
    if (e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA")) return

    if (e.key === "Escape") {
      e.preventDefault()
      this.element.classList.add("hidden")
      return
    }

    // y c — copy the displayed cell value to clipboard
    if (this._pendingY && Date.now() - this._pendingYAt < 800) {
      e.preventDefault()
      const verb = e.key
      this._pendingY = false
      if (verb === "c") {
        const pre = this.element.querySelector("pre")
        const text = pre?.textContent || ""
        navigator.clipboard.writeText(text)
      }
      return
    }
    if (e.key === "y") {
      e.preventDefault()
      this._pendingY = true
      this._pendingYAt = Date.now()
    }
  }
}
