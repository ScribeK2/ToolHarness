import { Controller } from "@hotwired/stimulus"

// Listens for global keyboard shortcuts.
// "/"   → focus the element with data-shortcuts-target="search"
// "Esc" → blur the currently focused input/textarea
export default class extends Controller {
  static targets = ["search"]

  connect() {
    this.boundHandler = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandler)
  }

  handleKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return

    if (event.key === "/" && !this.isTypingTarget(event.target) && this.hasSearchTarget) {
      event.preventDefault()
      this.searchTarget.focus()
      this.searchTarget.select?.()
    } else if (event.key === "Escape" && this.isTypingTarget(document.activeElement)) {
      document.activeElement.blur()
    }
  }

  isTypingTarget(el) {
    if (!el) return false
    const tag = el.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || el.isContentEditable
  }
}
