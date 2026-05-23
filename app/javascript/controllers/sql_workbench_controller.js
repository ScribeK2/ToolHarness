import { Controller } from "@hotwired/stimulus"

// Owns:
//  - modal NORMAL/INSERT focus toggling (ESC, i)
//  - Ctrl+Enter to submit the SQL form
//  - opening :c / :h / cell-detail overlays via dispatched events
// Grid navigation, copy verbs, and search are layered on in later tasks.
export default class extends Controller {
  static targets = ["editor", "form", "confirmed", "grid", "row", "status", "keymapHint"]
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
    this._renderModePill(mode)
    this._renderKeymapHint(mode)
  }

  _renderModePill(mode) {
    if (!this.hasStatusTarget) return
    const colors = ["text-mauve", "text-green", "text-cyan"]
    colors.forEach(c => this.statusTarget.classList.remove(c))
    if (mode === "INSERT")       { this.statusTarget.classList.add("text-green");  this.statusTarget.textContent = "-- INSERT --" }
    else if (mode === "COMMAND") { this.statusTarget.classList.add("text-cyan");   this.statusTarget.textContent = "-- COMMAND --" }
    else                         { this.statusTarget.classList.add("text-mauve");  this.statusTarget.textContent = "-- NORMAL --" }
    this.statusTarget.classList.add("font-bold")
  }

  _renderKeymapHint(mode) {
    if (!this.hasKeymapHintTarget) return
    const hints = {
      NORMAL:  "Ctrl+⏎ run · i edit · j/k row · / search · ? recipes · : cmd",
      INSERT:  "Ctrl+⏎ run · ESC nav · arrows in editor",
      COMMAND: "⏎ dispatch · ESC cancel · :db :w :c :d :save-recipe"
    }
    this.keymapHintTarget.textContent = hints[mode] || hints.NORMAL
  }

  handleKeydown(e) {
    // ignore when an overlay is open or another input has focus
    const overlayOpen = document.querySelector("#sql_connection_picker:not(.hidden), #sql_history_overlay:not(.hidden), #sql_cell_detail:not(.hidden), #sql_confirm_overlay:not(.hidden), #help_overlay:not(.hidden)")
    if (overlayOpen) return

    // Ctrl/Cmd+Enter runs the query regardless of mode. Users naturally lose
    // mode context when focus moves around (e.g. after a query completes); we
    // shouldn't gate "run" on a mode they can't easily see.
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      e.preventDefault()
      this.run()
      return
    }

    if (this.mode === "INSERT") {
      if (e.key === "Escape") {
        e.preventDefault()
        this.setMode("NORMAL")
      }
      return
    }

    // NORMAL
    if (e.target && e.target.tagName === "INPUT") return

    const grid = this.hasGridTarget ? this.gridTarget : null
    const rows = grid ? this.rowTargets : []
    const currentRow = rows[this.activeRowValue]
    const cellsInRow = () => currentRow ? currentRow.querySelectorAll("[data-cell]") : []

    // 1) Consume pending-y if a verb just arrived (must be BEFORE the switch
    //    so that j/k/h/l don't move the cursor before yank fires)
    if (this._pendingY && Date.now() - this._pendingYAt < 800) {
      e.preventDefault()
      const verb = e.key
      this._pendingY = false
      this.handleYank(verb)
      return
    }

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

    // 2) y starts a pending prefix
    if (e.key === "y" && this.mode === "NORMAL") {
      e.preventDefault()
      this._pendingY = true
      this._pendingYAt = Date.now()
      return
    }
    // 3) Y is standalone (full-result yank)
    if (e.key === "Y") {
      e.preventDefault(); this.handleYank("Y"); return
    }

    if (e.key === "/") {
      e.preventDefault()
      const q = window.prompt("/")
      if (!q) return
      this._searchTerm = q.toLowerCase()
      this._searchMatches = []
      this.rowTargets.forEach((r, ri) => {
        r.querySelectorAll("[data-cell]").forEach((c, ci) => {
          if ((c.dataset.value || "").toLowerCase().includes(this._searchTerm)) {
            this._searchMatches.push([ri, ci])
          }
        })
      })
      this._searchIdx = 0
      this.jumpToMatch()
      return
    }
    if (e.key === "n" && this._searchMatches?.length) {
      e.preventDefault()
      this._searchIdx = (this._searchIdx + 1) % this._searchMatches.length
      this.jumpToMatch(); return
    }
    if (e.key === "N" && this._searchMatches?.length) {
      e.preventDefault()
      this._searchIdx = (this._searchIdx - 1 + this._searchMatches.length) % this._searchMatches.length
      this.jumpToMatch(); return
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

  handleYank(verb) {
    const rows = this.rowTargets
    const row  = rows[this.activeRowValue]
    if (!row && verb !== "Y" && verb !== "J") return
    const cellOf = (r, i) => r.querySelectorAll("[data-cell]")[i]?.dataset?.value || ""
    const rowToTsv  = (r) => Array.from(r.querySelectorAll("[data-cell]")).map(c => c.dataset.value || "").join("\t")
    const rowToJson = (r) => {
      const headers = Array.from(document.querySelectorAll("#sql_result_panel th")).map(th => th.textContent.trim())
      const cells   = Array.from(r.querySelectorAll("[data-cell]")).map(c => c.dataset.value || "")
      return JSON.stringify(headers.reduce((acc, h, i) => (acc[h] = cells[i], acc), {}))
    }
    let text = ""
    switch (verb) {
      case "y": text = rowToTsv(row);  break  // y y → row TSV
      case "j": text = rowToJson(row); break  // y j → row JSON
      case "c": text = cellOf(row, this.activeColValue); break // y c → cell
      case "Y": text = rows.map(rowToTsv).join("\n"); break    // Y → full TSV
      case "J": text = "[" + rows.map(rowToJson).join(",") + "]"; break // y J → full JSON
      default: return
    }
    navigator.clipboard.writeText(text).then(() => {
      this.flash(`copied ${verb === "Y" || verb === "J" ? "all" : "row"}`)
    })
  }

  flash(msg) {
    if (!this.hasStatusTarget) return
    const previous = this.statusTarget.textContent
    this.statusTarget.textContent = `✓ ${msg}`
    clearTimeout(this._flashT)
    this._flashT = setTimeout(() => { this.statusTarget.textContent = previous }, 1200)
  }

  jumpToMatch() {
    if (!this._searchMatches?.length) return
    const [ri, ci] = this._searchMatches[this._searchIdx]
    this.activeRowValue = ri
    this.activeColValue = ci
    this.repaintActive(this.rowTargets)
    this.flash(`/${this._searchTerm} (${this._searchIdx + 1}/${this._searchMatches.length})`)
  }
}
