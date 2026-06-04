import { Controller } from "@hotwired/stimulus"
import { Prefs } from "lib/prefs"

// Theme picker. Lives on <body> so the status-bar pill and cmdline can reach it.
// Mirrors the sql-recipes pattern: owns a document keydown listener, bails when
// the overlay target is hidden. Live-previews on j/k, commits + persists on
// Enter/click, restores the saved theme on Esc.
//
// Opened via:
//   - the status-bar pill   (data-action="click->theme-picker#open")
//   - the :theme cmdline verb (dispatches "theme:open" / "theme:set")
export default class extends Controller {
  static targets = ["overlay", "row"]
  static values  = { active: { type: Number, default: 0 } }

  connect() {
    this._onKeydown = (e) => this._handleKey(e)
    this._onOpen    = () => this.open()
    this._onSet     = (e) => this._setDirect(e.detail && e.detail.key)
    document.addEventListener("keydown", this._onKeydown)
    document.addEventListener("theme:open", this._onOpen)
    document.addEventListener("theme:set", this._onSet)
    this._syncPill()
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
    document.removeEventListener("theme:open", this._onOpen)
    document.removeEventListener("theme:set", this._onSet)
  }

  // ---- metadata read from rows (no hard-coded theme list in JS) ----
  _meta(key) {
    const row = this.rowTargets.find(r => r.dataset.key === key)
    return row ? { label: row.dataset.label, scheme: row.dataset.scheme } : null
  }

  _savedKeyOrDefault() {
    const k = Prefs.get("theme", null)
    if (k && this._meta(k)) return k
    return this.rowTargets.length ? this.rowTargets[0].dataset.key : null
  }

  // ---- open / close ----
  open() {
    document.body.dataset.overlayActive = "true"
    this._restoreKey = this._savedKeyOrDefault()
    const idx = this.rowTargets.findIndex(r => r.dataset.key === this._restoreKey)
    this.activeValue = idx >= 0 ? idx : 0
    this.overlayTarget.classList.remove("hidden")
    this._repaint()
  }

  close() {
    delete document.body.dataset.overlayActive
    this.overlayTarget.classList.add("hidden")
  }

  // ---- apply / commit / cancel ----
  _apply(key) {
    const meta = this._meta(key)
    if (!meta) return
    const el = document.documentElement
    el.dataset.theme = key
    el.style.colorScheme = meta.scheme
  }

  _commit(key) {
    if (!this._meta(key)) return
    this._apply(key)
    Prefs.set("theme", key)
    this._syncPill()
    this.close()
  }

  _cancel() {
    this._apply(this._restoreKey || this._savedKeyOrDefault())
    this.close()
  }

  _setDirect(key) {
    if (key && this._meta(key)) this._commit(key)
  }

  // click handler on a row
  select(e) {
    this._commit(e.currentTarget.dataset.key)
  }

  // ---- status-bar pill text ----
  _syncPill() {
    const pill = document.querySelector("[data-theme-pill]")
    if (pill) pill.textContent = this._savedKeyOrDefault()
  }

  // ---- keyboard ----
  _handleKey(e) {
    if (!this.hasOverlayTarget || this.overlayTarget.classList.contains("hidden")) return
    const tag = e.target && e.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return
    const rows = this.rowTargets
    switch (e.key) {
      case "j":
        if (!rows.length) return
        e.preventDefault()
        this.activeValue = Math.min(rows.length - 1, this.activeValue + 1)
        this._previewActive()
        break
      case "k":
        if (!rows.length) return
        e.preventDefault()
        this.activeValue = Math.max(0, this.activeValue - 1)
        this._previewActive()
        break
      case "Enter":
        if (!rows.length) return
        e.preventDefault()
        this._commit(rows[this.activeValue].dataset.key)
        break
      case "Escape":
        e.preventDefault()
        this._cancel()
        break
    }
  }

  _previewActive() {
    this._repaint()
    this._apply(this.rowTargets[this.activeValue].dataset.key)
  }

  _repaint() {
    this.rowTargets.forEach((row, idx) => {
      row.classList.toggle("bg-elevated", idx === this.activeValue)
      const caret = row.querySelector("[data-caret]")
      if (caret) caret.textContent = idx === this.activeValue ? "▸" : " "
    })
  }
}
