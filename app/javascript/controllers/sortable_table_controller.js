import { Controller } from "@hotwired/stimulus"

// Click a <th data-sort-key="..."> in a <table data-controller="sortable-table">
// to sort the table by that column. Click again to toggle direction.
//
// Columns may declare data-sort-as="number" on the <th> for numeric ordering.
// Rows whose cell is empty or "—" sort last in ascending, first in descending.
export default class extends Controller {
  connect() {
    this.element.querySelectorAll("th[data-sort-key]").forEach((th) => {
      th.style.cursor = "pointer"
      th.setAttribute("role", "button")
      th.setAttribute("tabindex", "0")
      th.addEventListener("click", () => this.sortBy(th))
      th.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); this.sortBy(th) }
      })
    })
  }

  sortBy(th) {
    const key = th.dataset.sortKey
    const numeric = th.dataset.sortAs === "number"
    const tbody = this.element.querySelector("tbody")
    if (!tbody) return

    const direction = th.dataset.sortDirection === "asc" ? "desc" : "asc"
    this.element.querySelectorAll("th[data-sort-key]").forEach((other) => {
      delete other.dataset.sortDirection
    })
    th.dataset.sortDirection = direction

    const rows = Array.from(tbody.querySelectorAll("tr"))
    const sentinel = direction === "asc" ? Infinity : -Infinity

    rows.sort((a, b) => {
      const va = this.cellValue(a, key, numeric, sentinel)
      const vb = this.cellValue(b, key, numeric, sentinel)
      if (va === vb) return 0
      const cmp = numeric ? (va - vb) : String(va).localeCompare(String(vb))
      return direction === "asc" ? cmp : -cmp
    })
    rows.forEach((row) => tbody.appendChild(row))
  }

  cellValue(row, key, numeric, sentinel) {
    const cell = row.querySelector(`[data-sort-cell="${key}"]`)
    if (!cell) return sentinel
    const raw = (cell.dataset.sortValue ?? cell.textContent ?? "").trim()
    if (raw === "" || raw === "—") return sentinel
    if (numeric) {
      const n = parseFloat(raw)
      return Number.isFinite(n) ? n : sentinel
    }
    return raw
  }
}
