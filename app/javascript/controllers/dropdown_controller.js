import { Controller } from "@hotwired/stimulus"

// Attached to a native <details> dropdown. Adds the two dismissal
// affordances <details> lacks: Escape and clicking outside. Keydown is
// captured so a consumed Escape never reaches the mode controller's
// document-level handler.
export default class extends Controller {
  connect() {
    this.onKeydown = (e) => {
      if (e.key === "Escape" && this.element.open) {
        e.preventDefault()
        e.stopPropagation()
        this.element.open = false
      }
    }
    this.onClick = (e) => {
      if (this.element.open && !this.element.contains(e.target)) {
        this.element.open = false
      }
    }
    document.addEventListener("keydown", this.onKeydown, true)
    document.addEventListener("click", this.onClick)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown, true)
    document.removeEventListener("click", this.onClick)
  }
}
