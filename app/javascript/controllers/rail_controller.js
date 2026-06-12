import { Controller } from "@hotwired/stimulus"
import { Prefs } from "lib/prefs"

// Wires the tool rail to mode events.
//   rail:next / rail:prev — j/k navigation
//   rail:filter           — t opens an inline filter input
//   rail:slot (slot: N)   — 1..9 jump to pinned slot
//   rail:top              — gg jump to top
export default class extends Controller {
  static targets = ["item", "system"]
  static values  = { active: String }

  connect() {
    this.onNext   = () => this.move(+1)
    this.onPrev   = () => this.move(-1)
    this.onFilter = () => this.openFilter()
    this.onSlot   = (e) => this.jumpSlot(e.detail.slot)
    this.onTop    = () => this.move(-Infinity)
    document.addEventListener("rail:next", this.onNext)
    document.addEventListener("rail:prev", this.onPrev)
    document.addEventListener("rail:filter", this.onFilter)
    document.addEventListener("rail:slot", this.onSlot)
    document.addEventListener("rail:top", this.onTop)
    const found = this.itemTargets.findIndex(el => el.dataset.toolKey === this.activeValue)
    this.index = found >= 0 ? found : null
    this.refreshOutline()
  }

  disconnect() {
    document.removeEventListener("rail:next", this.onNext)
    document.removeEventListener("rail:prev", this.onPrev)
    document.removeEventListener("rail:filter", this.onFilter)
    document.removeEventListener("rail:slot", this.onSlot)
    document.removeEventListener("rail:top", this.onTop)
  }

  move(delta) {
    const items = this.itemTargets
    if (items.length === 0) return
    if (delta === -Infinity || this.index === null) {
      this.index = 0
    } else {
      this.index = (this.index + delta + items.length) % items.length
    }
    this.refreshOutline()
    items[this.index].scrollIntoView({ block: "nearest" })
    // Enter on focused item triggers click via standard keyboard handling
  }

  refreshOutline() {
    this.itemTargets.forEach((el, i) => {
      if (i === this.index) {
        el.classList.add("outline", "outline-1", "outline-accent-2")
      } else {
        el.classList.remove("outline", "outline-1", "outline-accent-2")
      }
    })
  }

  openFilter() {
    const existing = this.element.querySelector("[data-rail-filter]")
    if (existing) { existing.focus(); return }
    const input = document.createElement("input")
    input.type = "text"
    input.placeholder = "filter…"
    input.setAttribute("data-rail-filter", "")
    input.className = "block w-full box-border px-3 my-2 text-[11px]"
    this.element.prepend(input)
    input.focus()
    input.addEventListener("input", () => this.applyFilter(input.value))
    input.addEventListener("keydown", (e) => {
      if (e.key === "Escape") { input.remove(); this.applyFilter("") }
    })
  }

  applyFilter(q) {
    const needle = q.toLowerCase()
    this.itemTargets.forEach(el => {
      const txt = el.textContent.toLowerCase()
      el.style.opacity = (!needle || txt.includes(needle)) ? "" : "0.3"
    })
  }

  jumpSlot(n) {
    const slots = Prefs.get("pinned", null) ||
      JSON.parse(document.querySelector("[data-default-slots]")?.dataset.defaultSlots || "[]")
    const key = slots[n - 1]
    if (!key) return
    const link = this.itemTargets.find(el => el.dataset.toolKey === key)
    if (link) link.click()
  }
}
