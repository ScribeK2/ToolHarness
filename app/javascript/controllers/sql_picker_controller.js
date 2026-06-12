import { Controller } from "@hotwired/stimulus"

// Keyboard handling inside the SQL connection picker overlay.
//
//  j / k   — move highlight down / up
//  Enter   — submit highlighted row (connect)
//  n       — open new-profile form via server Turbo Stream
//  ESC     — close the overlay
//
// Edit (e) and delete (dd) are deferred to a follow-up.
export default class extends Controller {
  static targets = ["row"]
  static values  = { active: { type: Number, default: 0 } }

  connect() {
    this._onKeydown = (e) => this._handleKey(e)
    document.addEventListener("keydown", this._onKeydown)
    this._repaint()
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  // ── private ──────────────────────────────────────────────────────────────

  _handleKey(e) {
    // Only respond while the picker is visible.
    if (this.element.classList.contains("hidden")) return

    // Don't intercept when the user is typing inside form inputs.
    const tag = e.target && e.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return

    const rows = this.rowTargets

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
        rows[this.activeValue]?.querySelector("button")?.click()
        break

      case "n":
        e.preventDefault()
        fetch("/workbench/sql/profiles/new", {
          headers: { Accept: "text/vnd.turbo-stream.html" }
        })
          .then((r) => r.text())
          .then((html) => Turbo.renderStreamMessage(html))
        break

      case "Escape":
        e.preventDefault()
        this.element.classList.add("hidden")
        break
    }
  }

  _repaint() {
    this.rowTargets.forEach((row, idx) => {
      // Each row target is a <form>; the visible element is the <button> inside.
      const btn = row.querySelector("button")
      if (!btn) return
      btn.classList.toggle("bg-elevated", idx === this.activeValue)
      const caret = row.querySelector("[data-caret]")
      if (caret) caret.textContent = idx === this.activeValue ? "▸" : " "
    })
  }
}
