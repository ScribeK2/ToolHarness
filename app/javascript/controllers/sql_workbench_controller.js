import { Controller } from "@hotwired/stimulus"

// Owns:
//  - modal NORMAL/INSERT focus toggling (ESC, i)
//  - Ctrl+Enter to submit the SQL form
//  - opening :c / :h / cell-detail overlays via dispatched events
// Grid navigation, copy verbs, and search are layered on in later tasks.
export default class extends Controller {
  static targets = ["editor", "form", "confirmed", "grid", "row", "status"]
  static values  = { activeRow: Number, activeCol: Number }

  connect() {
    this.onKeydown = (e) => this.handleKeydown(e)
    document.addEventListener("keydown", this.onKeydown)
    this.setMode("NORMAL")
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  setMode(mode) {
    this.mode = mode
    document.body.dataset.modeStateValue = mode
    if (mode === "INSERT" && this.hasEditorTarget) this.editorTarget.focus()
    if (mode === "NORMAL" && this.hasEditorTarget) this.editorTarget.blur()
  }

  handleKeydown(e) {
    // ignore when an overlay is open or another input has focus
    const overlayOpen = document.querySelector("#sql_connection_picker:not(.hidden), #sql_history_overlay:not(.hidden), #sql_cell_detail:not(.hidden), #sql_confirm_overlay:not(.hidden), #help_overlay:not(.hidden)")
    if (overlayOpen) return

    if (this.mode === "INSERT") {
      if (e.key === "Escape") {
        e.preventDefault()
        this.setMode("NORMAL")
      } else if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        this.run()
      }
      return
    }

    // NORMAL
    if (e.target && e.target.tagName === "INPUT") return

    const grid = this.hasGridTarget ? this.gridTarget : null
    const rows = grid ? this.rowTargets : []
    const currentRow = rows[this.activeRowValue]
    const cellsInRow = () => currentRow ? currentRow.querySelectorAll("[data-cell]") : []

    switch (e.key) {
      case "i": e.preventDefault(); this.setMode("INSERT"); break
      case "Enter": e.preventDefault(); this.openCellDetail(); break
      case "j":
        if (rows.length === 0) break
        e.preventDefault()
        this.activeRowValue = Math.min(rows.length - 1, this.activeRowValue + 1)
        this.repaintActive(rows); break
      case "k":
        if (rows.length === 0) break
        e.preventDefault()
        this.activeRowValue = Math.max(0, this.activeRowValue - 1)
        this.repaintActive(rows); break
      case "l":
        if (rows.length === 0) break
        e.preventDefault()
        this.activeColValue = Math.min(cellsInRow().length - 1, this.activeColValue + 1)
        this.repaintActive(rows); break
      case "h":
        if (rows.length === 0) break
        e.preventDefault()
        this.activeColValue = Math.max(0, this.activeColValue - 1)
        this.repaintActive(rows); break
      case "0":
        if (rows.length === 0) break
        e.preventDefault(); this.activeColValue = 0; this.repaintActive(rows); break
      case "$":
        if (rows.length === 0) break
        e.preventDefault(); this.activeColValue = cellsInRow().length - 1; this.repaintActive(rows); break
      case "G":
        if (rows.length === 0) break
        e.preventDefault(); this.activeRowValue = rows.length - 1; this.repaintActive(rows); break
      case "g":
        // simple gg double-tap
        if (rows.length === 0) break
        this._lastG = (Date.now() - (this._lastGAt || 0) < 400)
        this._lastGAt = Date.now()
        if (this._lastG) {
          e.preventDefault(); this.activeRowValue = 0; this.repaintActive(rows)
        }
        break
    }
  }

  run() {
    if (!this.hasFormTarget) return
    if (this.hasConfirmedTarget) this.confirmedTarget.value = "false"
    this.formTarget.requestSubmit()
  }

  openCellDetail() {
    if (!this.hasGridTarget) return
    const row = this.activeRowValue
    const col = this.activeColValue
    const runEl = document.querySelector("[data-run-id]")
    const runId = runEl?.dataset.runId
    if (!runId) return
    fetch(`/workbench/sql/cells/${runId}?row=${row}&col=${col}`, {
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    }).then(r => r.text()).then(html => Turbo.renderStreamMessage(html))
  }

  repaintActive(rows) {
    rows.forEach((r) => r.classList.remove("bg-elevated"))
    rows.forEach((r) => r.querySelectorAll("[data-cell]").forEach((c) => c.classList.remove("outline", "outline-1", "outline-cyan")))
    const row = rows[this.activeRowValue]
    if (!row) return
    row.classList.add("bg-elevated")
    const cells = row.querySelectorAll("[data-cell]")
    const cell = cells[this.activeColValue]
    if (cell) cell.classList.add("outline", "outline-1", "outline-cyan")
    row.scrollIntoView({ block: "nearest" })
  }
}
