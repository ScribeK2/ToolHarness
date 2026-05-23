import { Controller } from "@hotwired/stimulus"

// Keyboard navigation inside the SQL history overlay.
//  - j / k   : highlight next / prev row
//  - Enter   : load highlighted SQL into the workbench editor, close overlay
//  - e       : load + focus editor for editing
//  - r       : load + immediately re-run (submit the workbench form)
//  - ESC     : close overlay
export default class extends Controller {
  static targets = ["row"]
  static values  = { active: { type: Number, default: 0 } }

  connect() {
    this.onKeydown = (e) => this.handleKey(e)
    document.addEventListener("keydown", this.onKeydown)
    this.repaint()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  handleKey(e) {
    if (this.element.classList.contains("hidden")) return
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
        this.loadAndClose()
        break
      case "e":
        if (!rows.length) return
        e.preventDefault()
        this.loadAndClose({ focus: true })
        break
      case "r":
        if (!rows.length) return
        e.preventDefault()
        this.loadAndClose({ rerun: true })
        break
      case "Escape":
        e.preventDefault()
        this.element.classList.add("hidden")
        break
    }
  }

  loadAndClose({ focus = false, rerun = false } = {}) {
    const row = this.rowTargets[this.activeValue]
    const sql = row?.dataset?.sql || ""
    const editor = document.querySelector("[data-sql-workbench-target='editor']")
    if (editor) {
      editor.value = sql
      if (focus) editor.focus()
    }
    this.element.classList.add("hidden")
    if (rerun) {
      const form = document.querySelector("[data-sql-workbench-target='form']")
      form?.requestSubmit?.()
    }
  }

  repaint() {
    this.rowTargets.forEach((row, idx) => {
      row.classList.toggle("bg-elevated", idx === this.activeValue)
    })
  }
}
