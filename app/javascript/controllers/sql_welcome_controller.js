import { Controller } from "@hotwired/stimulus"

// Keyboard handling inside the welcome card (per-profile first-connect card).
//
//  ESC / Enter  — dismiss (remove from DOM)
//  1 / 2 / 3    — load corresponding starter SQL into the editor + dismiss
//  4            — dismiss + open the recipe palette
//
// Dismissal is purely client-side. `welcome_seen_profiles` was already updated
// in Sql::SessionsController#create before the render, so the card never
// returns for this profile-key in this browser cookie.
export default class extends Controller {
  static targets = ["row"]

  connect() {
    this._onKeydown = (e) => this._handleKey(e)
    document.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  _handleKey(e) {
    if (this.element.classList.contains("hidden")) return
    const tag = e.target && e.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return

    if (e.key === "Escape" || e.key === "Enter") {
      e.preventDefault()
      this._dismiss()
      return
    }
    if (e.key === "1") { e.preventDefault(); this._loadAndDismiss(0); return }
    if (e.key === "2") { e.preventDefault(); this._loadAndDismiss(1); return }
    if (e.key === "3") { e.preventDefault(); this._loadAndDismiss(2); return }
    if (e.key === "4") {
      e.preventDefault()
      this._dismiss()
      // Defer to the workbench controller's palette-open helper by simulating
      // a `?` keypress event. The workbench controller listens on document.
      const ev = new KeyboardEvent("keydown", { key: "?", bubbles: true })
      document.dispatchEvent(ev)
      return
    }
  }

  _loadAndDismiss(idx) {
    const row = this.rowTargets[idx]
    if (!row) return this._dismiss()
    const sql = row.dataset.sql || ""
    const editor = document.querySelector("[data-sql-workbench-target='editor']")
    if (editor) editor.value = sql
    this._dismiss()
  }

  _dismiss() {
    this.element.remove()
  }
}
