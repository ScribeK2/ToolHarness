import { Controller } from "@hotwired/stimulus"

// Keyboard navigation for the investigation surface (rendered inside #result_panel).
// Claims keyboard ownership via body[data-investigation-active] so the global
// mode_controller yields (same idiom as sqlWorkbenchActive). While active, the
// rail's global shortcuts are suspended; Esc returns to the workbench.
//  - j / k : move the highlight down / up the step list
//  - Enter : open the highlighted step (Turbo-navigate to ?step=<id>)
//  - Esc   : return to /workbench
export default class extends Controller {
  static targets = ["row"]
  static values  = { active: { type: Number, default: 0 } }

  connect() {
    document.body.dataset.investigationActive = "true"
    this.onKeydown = (e) => this.handleKey(e)
    document.addEventListener("keydown", this.onKeydown)
    this.syncActiveToSelected()
    this.repaint()
  }

  disconnect() {
    delete document.body.dataset.investigationActive
    document.removeEventListener("keydown", this.onKeydown)
  }

  // Start the highlight on the server-selected step, if any.
  syncActiveToSelected() {
    const idx = this.rowTargets.findIndex((r) => r.dataset.selected === "true")
    if (idx >= 0) this.activeValue = idx
  }

  handleKey(e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return
    if (e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT")) return

    const rows = this.rowTargets
    switch (e.key) {
      case "j":
        if (!rows.length) return
        e.preventDefault()
        this.activeValue = Math.min(rows.length - 1, this.activeValue + 1)
        this.repaint()
        break
      case "k":
        if (!rows.length) return
        e.preventDefault()
        this.activeValue = Math.max(0, this.activeValue - 1)
        this.repaint()
        break
      case "Enter":
        if (!rows.length) return
        e.preventDefault()
        this.openActive()
        break
      case "Escape":
        e.preventDefault()
        Turbo.visit("/workbench")
        break
    }
  }

  openActive() {
    const url = this.rowTargets[this.activeValue]?.dataset?.stepUrl
    if (url) Turbo.visit(url)
  }

  repaint() {
    this.rowTargets.forEach((row, idx) => {
      row.classList.toggle("bg-elevated", idx === this.activeValue)
    })
  }
}
