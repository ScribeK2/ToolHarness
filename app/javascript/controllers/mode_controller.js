import { Controller } from "@hotwired/stimulus"

// Attached to <html>. Tracks NORMAL / INSERT / CMD / SEARCH.
// Captures global keydown and dispatches events on `document`:
//   modeChange   detail: { from, to }
//   keyAction    detail: { key, code, prevented(): true } in NORMAL mode
//   cmdRequest   detail: {} when ":" is pressed
//   searchRequest detail: {} when "/" is pressed
//   helpToggle   detail: {} when "?" is pressed in NORMAL
//   runRequest   detail: {} when "r" is pressed in NORMAL
//   yankRequest  detail: { sequence } when "y..." is pressed in NORMAL
//
// Other controllers (cmdline, rail, copy) listen for these events.
export default class extends Controller {
  static values = { state: { type: String, default: "NORMAL" } }

  connect() {
    this.boundKey = this.handleKey.bind(this)
    this.boundFocus = this.handleFocus.bind(this)
    document.addEventListener("keydown", this.boundKey)
    document.addEventListener("focusin", this.boundFocus)
    this.applyMode("NORMAL", { silent: true })
    this.pending = "" // for multi-key sequences like "yy", "gh", "dd"
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKey)
    document.removeEventListener("focusin", this.boundFocus)
  }

  setMode(name) {
    const next = name.toUpperCase()
    this.applyMode(next)
  }

  applyMode(next, { silent = false } = {}) {
    const prev = this.stateValue
    this.stateValue = next
    const root = this.element
    root.classList.remove("mode-normal", "mode-insert", "mode-cmd", "mode-search")
    root.classList.add(`mode-${next.toLowerCase()}`)
    const badge = document.querySelector("[data-mode-badge]")
    if (badge) {
      badge.textContent = next
      badge.className = "px-1.5 font-bold mr-2 text-bg " + this.badgeBgClass(next)
    }
    if (!silent) {
      document.dispatchEvent(new CustomEvent("modeChange", { detail: { from: prev, to: next } }))
    }
  }

  badgeBgClass(name) {
    return {
      NORMAL: "bg-green",
      INSERT: "bg-orange",
      CMD:    "bg-cyan",
      SEARCH: "bg-purple"
    }[name] || "bg-mute"
  }

  handleFocus(event) {
    const el = event.target
    if (this.isTypingTarget(el) && this.stateValue === "NORMAL") {
      this.applyMode("INSERT")
    }
  }

  handleKey(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return

    // INSERT — only Esc returns to NORMAL
    if (this.stateValue === "INSERT") {
      if (event.key === "Escape") {
        event.target.blur?.()
        this.applyMode("NORMAL")
        event.preventDefault()
      }
      return
    }

    // CMD or SEARCH — Esc returns to NORMAL (their own controllers also handle Enter)
    if (this.stateValue === "CMD" || this.stateValue === "SEARCH") {
      if (event.key === "Escape") this.applyMode("NORMAL")
      return
    }

    // NORMAL mode — single & multi-key actions
    if (event.key === "Escape") { this.pending = ""; return }

    const k = event.key

    // Multi-key sequences
    if (this.pending) {
      const seq = this.pending + k
      this.pending = ""
      event.preventDefault()
      if (seq === "yy") return this.dispatchYank("summary")
      if (seq === "yr") return this.dispatchYank("raw")
      if (seq.startsWith("y") && seq.length === 2) return this.dispatchYank(seq[1])
      if (seq === "gg") return document.dispatchEvent(new Event("rail:top"))
      if (seq === "gh") return Turbo.visit("/workbench?view=history")
      if (seq === "ge") return Turbo.visit("/workbench?view=history&filter=" + encodeURIComponent("severity>=warn expires<30d"))
      if (seq === "dd") return document.dispatchEvent(new Event("history:delete"))
      if (seq === "ej") return document.dispatchEvent(new CustomEvent("history:export", { detail: { format: "json" } }))
      if (seq === "ec") return document.dispatchEvent(new CustomEvent("history:export", { detail: { format: "csv" } }))
      if (seq === "em") return document.dispatchEvent(new CustomEvent("history:export", { detail: { format: "md" } }))
      return
    }

    // Start of a multi-key sequence
    if (["y", "g", "d", "e"].includes(k)) {
      this.pending = k
      event.preventDefault()
      // clear pending if no follow-up within 1s
      clearTimeout(this.pendingTimeout)
      this.pendingTimeout = setTimeout(() => { this.pending = "" }, 1000)
      return
    }

    // Single-key actions
    if (k === "/") {
      event.preventDefault()
      const el = document.querySelector("[data-workbench-target='input']")
      if (el) { el.focus(); el.select?.() }
      this.applyMode("SEARCH")
      return
    }
    if (k === ":") {
      event.preventDefault()
      document.dispatchEvent(new Event("cmd:open"))
      return
    }
    if (k === "?") {
      event.preventDefault()
      document.dispatchEvent(new Event("help:toggle"))
      return
    }
    if (k === "r") {
      event.preventDefault()
      document.dispatchEvent(new Event("run:request"))
      return
    }
    if (k === "Y") {
      event.preventDefault()
      return this.dispatchYank("summary")
    }
    if (k === "x") {
      event.preventDefault()
      document.dispatchEvent(new Event("result:clear"))
      return
    }
    if (k === "t") {
      event.preventDefault()
      document.dispatchEvent(new Event("rail:filter"))
      return
    }
    if (k === "j" || k === "ArrowDown") {
      event.preventDefault()
      document.dispatchEvent(new Event("rail:next"))
      return
    }
    if (k === "k" || k === "ArrowUp") {
      event.preventDefault()
      document.dispatchEvent(new Event("rail:prev"))
      return
    }
    if (/^[1-9]$/.test(k)) {
      event.preventDefault()
      document.dispatchEvent(new CustomEvent("rail:slot", { detail: { slot: parseInt(k, 10) } }))
      return
    }
  }

  dispatchYank(target) {
    document.dispatchEvent(new CustomEvent("yank:request", { detail: { target } }))
  }

  isTypingTarget(el) {
    if (!el) return false
    const tag = el.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || el.isContentEditable
  }
}
