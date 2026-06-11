import { Controller } from "@hotwired/stimulus"

// Replaces clipboard_controller. Handles five flavors of copy:
//   y s → summary  (data-copy-text-value)
//   y F → full     (window.toolRunFullText, set per-run)
//   y r → raw      (window.toolRunRawJson, set per-run)
//   y <letter> → a specific result section (matches [data-section="<letter>"])
//   click → copyValue: a single value (data-copy-value), e.g. a kv field or table cell
// Listens for `yank:request` from mode controller; copyValue is mouse-driven.
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
    } else if (target === "full" || target === "F") {
      text = this.getFull()
    } else {
      text = this.getSection(target)
    }
    if (text) this.write(text)
  }

  copySummary() { this.write(this.textValue) }
  copyFull() { this.write(this.getFull()) }
  copySection() { this.write(this.getSection(this.sectionValue)) }

  copyValue(e) {
    const el = e.currentTarget
    this.write(el.dataset.copyValue ?? el.innerText)
  }

  getSummary() {
    // The summary button has data-copy-text-value="…"
    const el = document.querySelector("[data-copy-text-value]")
    return el ? el.dataset.copyTextValue : ""
  }

  getRaw() {
    return window.toolRunRawJson || ""
  }

  getFull() {
    return window.toolRunFullText || ""
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
