import { Controller } from "@hotwired/stimulus"

// Keyboard handling inside the SQL recipe palette overlay.
//
//  j / k    — move highlight down / up (unified across STARTERS + SAVED)
//  Enter    — load selected recipe SQL into the workbench editor and close
//  d        — delete selected SAVED recipe (with [y/n] inline confirm in footer)
//  /        — enter filter mode (input field, case-insensitive substring)
//  ESC      — close overlay (and exit filter mode if active)
//
// Pattern: same as sql_picker_controller / sql_history_controller — owns its
// document keydown listener, bails when the overlay element has `hidden`.
export default class extends Controller {
  static targets = ["row"]
  static values  = { active: { type: Number, default: 0 } }

  connect() {
    this._onKeydown = (e) => this._handleKey(e)
    document.addEventListener("keydown", this._onKeydown)
    this._filterMode = false
    this._pendingDelete = null
    this._repaint()
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  _handleKey(e) {
    if (this.element.classList.contains("hidden")) return

    // Filter-mode capture: while in filter mode, route keys to the filter input.
    if (this._filterMode) {
      if (e.key === "Escape") { e.preventDefault(); this._exitFilter(); return }
      if (e.key === "Enter")  { e.preventDefault(); this._exitFilter(); return }
      return // let the input handle other keys
    }

    // Pending-delete confirm: [y] confirms delete, anything else cancels.
    if (this._pendingDelete) {
      e.preventDefault()
      const name = this._pendingDelete
      this._pendingDelete = null
      if (e.key === "y") this._doDelete(name)
      else               this._setFooter(null) // cancel
      return
    }

    const tag = e.target && e.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return

    const rows = this._visibleRows()

    switch (e.key) {
      case "j":
        if (!rows.length) return
        e.preventDefault()
        this.activeValue = Math.min(rows.length - 1, this.activeValue + 1)
        this._repaint()
        break

      case "k":
        if (!rows.length) return
        e.preventDefault()
        this.activeValue = Math.max(0, this.activeValue - 1)
        this._repaint()
        break

      case "Enter":
        if (!rows.length) return
        e.preventDefault()
        this._loadAndClose(rows[this.activeValue])
        break

      case "d":
        if (!rows.length) return
        e.preventDefault()
        {
          const row = rows[this.activeValue]
          if (row.dataset.source !== "saved") {
            this._setFooter("cannot delete starter")
            setTimeout(() => this._setFooter(null), 1500)
            return
          }
          this._pendingDelete = row.dataset.name
          this._setFooter(`delete '${row.dataset.name}'? [y/n]`)
        }
        break

      case "/":
        e.preventDefault()
        this._enterFilter()
        break

      case "Escape":
        e.preventDefault()
        this.element.classList.add("hidden")
        break
    }
  }

  _loadAndClose(row) {
    const sql = row.dataset.sql || ""
    const editor = document.querySelector("[data-sql-workbench-target='editor']")
    if (editor) {
      editor.value = sql
      // Position selection over the first <placeholder> if present
      const m = sql.match(/<[a-z_]+>/i)
      if (m) {
        const start = sql.indexOf(m[0])
        editor.focus()
        editor.setSelectionRange(start, start + m[0].length)
        // Placeholder is selected — switch to INSERT so the next keystroke
        // replaces it cleanly and the mode pill matches what the rep sees.
        document.dispatchEvent(new Event("sql-workbench:insert"))
      }
    }
    this.element.classList.add("hidden")
  }

  _doDelete(name) {
    fetch(`/workbench/sql/recipes/${encodeURIComponent(name)}`, {
      method: "DELETE",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      }
    }).then(r => r.text()).then(html => Turbo.renderStreamMessage(html))
  }

  _enterFilter() {
    this._filterMode = true
    const footer = this._footerEl()
    if (!footer) return
    footer.innerHTML = `<input data-sql-recipes-target="filter" autocomplete="off" autofocus
      class="bg-bg border border-line w-full px-1" placeholder="/filter">`
    const input = footer.querySelector("input")
    input?.addEventListener("input", () => this._applyFilter(input.value))
  }

  _exitFilter() {
    this._filterMode = false
    this._applyFilter("")
    this._setFooter(null)
  }

  _applyFilter(term) {
    const needle = term.toLowerCase()
    this.rowTargets.forEach(row => {
      const hay = (row.dataset.name + " " + row.dataset.sql).toLowerCase()
      row.classList.toggle("hidden", needle.length > 0 && !hay.includes(needle))
    })
    this.activeValue = 0
    this._repaint()
  }

  _visibleRows() {
    return this.rowTargets.filter(r => !r.classList.contains("hidden"))
  }

  _setFooter(msg) {
    const footer = this._footerEl()
    if (!footer) return
    if (msg === null) {
      footer.innerHTML = "j/k nav · ⏎ load · d delete sav.<br>/ filter · ESC close"
    } else {
      footer.textContent = msg
    }
  }

  _footerEl() {
    // Footer is the last child div of the inner card — keymap hint location.
    return this.element.querySelector(".text-mute.text-\\[10px\\].mt-3")
  }

  _repaint() {
    const rows = this._visibleRows()
    rows.forEach((row, idx) => {
      row.classList.toggle("bg-elevated", idx === this.activeValue)
      const caret = row.querySelector("span.text-accent")
      if (caret) caret.textContent = idx === this.activeValue ? "▸" : " "
    })
  }
}
