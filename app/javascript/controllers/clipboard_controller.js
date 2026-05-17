import { Controller } from "@hotwired/stimulus"

// data-controller="clipboard"
// data-clipboard-text-value="text to copy"  (preferred)
// or wrap content with data-clipboard-target="source"
//
// data-action="click->clipboard#copy"
export default class extends Controller {
  static targets = ["source", "label"]
  static values  = { text: String, copiedLabel: { type: String, default: "Copied" } }

  copy(event) {
    event?.preventDefault()
    const text = this.hasTextValue && this.textValue.length
      ? this.textValue
      : (this.hasSourceTarget ? this.sourceTarget.innerText.trim() : "")

    if (!text) return

    navigator.clipboard.writeText(text).then(() => this.flashCopied()).catch(() => {
      // Fallback for older browsers / non-secure contexts
      const ta = document.createElement("textarea")
      ta.value = text
      ta.setAttribute("readonly", "")
      ta.style.position = "absolute"
      ta.style.left = "-9999px"
      document.body.appendChild(ta)
      ta.select()
      try { document.execCommand("copy") } catch (_) {}
      document.body.removeChild(ta)
      this.flashCopied()
    })
  }

  flashCopied() {
    const target = this.hasLabelTarget ? this.labelTarget : this.element
    const original = target.textContent
    target.textContent = this.copiedLabelValue
    target.classList.add("text-success")
    setTimeout(() => {
      target.textContent = original
      target.classList.remove("text-success")
    }, 1500)
  }
}
