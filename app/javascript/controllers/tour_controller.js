import { Controller } from "@hotwired/stimulus"
import { Prefs } from "lib/prefs"

const STEPS = [
  { selector: "[data-workbench-target='input']", text: "Type a target — domain, email, IP — and press Enter or click RUN." },
  { selector: "[data-controller='rail']",        text: "Tool rail. Press j/k to move, t to filter, 1–9 for pinned slots, Enter to switch." },
  { selector: "#cmdline_wrap, [data-mode-badge]", text: "Press : to open the command line. Try :help anytime." },
  { selector: "[data-status='hints']",            text: "Press ? for a full help overlay. Re-open with :help tour." }
]

export default class extends Controller {
  connect() {
    if (Prefs.get("tour_done", false)) return
    // Allow re-trigger via :help tour
    this.onTrigger = () => this.start()
    document.addEventListener("tour:start", this.onTrigger)
    this.start()
  }

  disconnect() {
    document.removeEventListener("tour:start", this.onTrigger)
  }

  start() {
    this.idx = 0
    this.show()
  }

  show() {
    this.dismissCurrent()
    if (this.idx >= STEPS.length) {
      Prefs.set("tour_done", true)
      return
    }
    const { selector, text } = STEPS[this.idx]
    const target = document.querySelector(selector)
    if (!target) { this.idx++; return this.show() }

    const rect = target.getBoundingClientRect()
    const tip = document.createElement("div")
    tip.className = "fixed border border-cyan bg-bg text-fg text-xs p-2 z-50 max-w-xs"
    tip.style.top = (rect.bottom + 6) + "px"
    tip.style.left = (rect.left + 6) + "px"
    tip.innerHTML = `<div class="mb-2">${text}</div>
      <div class="flex justify-between text-mute">
        <span>step ${this.idx + 1}/${STEPS.length}</span>
        <button data-tour-action="next" class="text-cyan">[next ⏎]</button>
        <button data-tour-action="skip" class="text-mute ml-2">[skip Esc]</button>
      </div>`
    document.body.appendChild(tip)
    this.currentTip = tip

    this.onClick = (e) => {
      if (e.target.dataset.tourAction === "next") this.advance()
      if (e.target.dataset.tourAction === "skip") { this.dismissCurrent(); Prefs.set("tour_done", true) }
    }
    tip.addEventListener("click", this.onClick)

    this.onKey = (e) => {
      if (e.key === "Escape") { this.dismissCurrent(); Prefs.set("tour_done", true) }
      if (e.key === "Enter")  { this.advance() }
    }
    document.addEventListener("keydown", this.onKey, { once: true })
  }

  advance() { this.idx++; this.show() }

  dismissCurrent() {
    if (this.currentTip) this.currentTip.remove()
    this.currentTip = null
  }
}
