import { Controller } from "@hotwired/stimulus"

// Replaces clipboard_controller. Handles three flavors of copy:
//   y s → summary  (data-copy-text-value)
//   y r → raw      (window.toolRunRawJson, set per-run)
//   y <letter> → a specific result section (matches [data-section="<letter>"])
// Listens for `yank:request` from mode controller.
export default class extends Controller {
  static values = { text: String, section: String }

  connect() {
    this.onYank = (e) => this.handleYank(e.detail.target)
    document.addEventListener("yank:request", this.onYank)
  }

  disconnect() {
    document.removeEventListener("yank:request", this.onYank)
  }

  handleYank(target) {
    let text
    if (target === "summary" || target === "s") {
      text = this.getSummary()
    } else if (target === "raw" || target === "r") {
      text = this.getRaw()
    } else {
      text = this.getSection(target)
    }
    if (text) this.write(text)
  }

  copySummary() { this.write(this.textValue) }
  copySection() { this.write(this.getSection(this.sectionValue)) }

  getSummary() {
    // The summary button has data-copy-text-value="…"
    const el = document.querySelector("[data-copy-text-value]")
    return el ? el.dataset.copyTextValue : ""
  }

  getRaw() {
    return window.toolRunRawJson || ""
  }

  getSection(letter) {
    const el = document.querySelector(`[data-section="${letter}"]`)
    if (!el) return ""
    return el.innerText.trim()
  }

  write(text) {
    if (!text) return
    navigator.clipboard.writeText(text).then(
      () => this.flash(`copied (${text.length} chars)`),
      () => this.fallback(text)
    )
  }

  fallback(text) {
    const ta = document.createElement("textarea")
    ta.value = text
    ta.style.position = "absolute"
    ta.style.left = "-9999px"
    document.body.appendChild(ta)
    ta.select()
    try { document.execCommand("copy") } catch (_) {}
    document.body.removeChild(ta)
    this.flash(`copied (${text.length} chars)`)
  }

  flash(msg) {
    const hints = document.querySelector("[data-status='hints']")
    if (!hints) return
    const original = hints.textContent
    hints.textContent = `▸ ${msg}`
    hints.classList.add("text-cyan")
    clearTimeout(this.flashTimeout)
    this.flashTimeout = setTimeout(() => {
      hints.textContent = original
      hints.classList.remove("text-cyan")
    }, 1500)
  }
}
