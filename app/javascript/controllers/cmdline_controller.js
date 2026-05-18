import { Controller } from "@hotwired/stimulus"
import { Prefs } from "lib/prefs"

const KNOWN = ["run", "tool", "target", "copy", "export", "pin", "history",
               "expiring", "raw", "help", "set", "purge", "q"]
const CLIENT_ONLY = ["copy", "set", "q", "raw", "tool", "target", "pin", "expiring", "history", "help"]

export default class extends Controller {
  static targets = ["input", "runId"]

  connect() {
    this.history = Prefs.get("cmd_history", [])
    this.historyIdx = -1
    this.onOpen = () => this.open()
    this.onKey = (e) => this.handleKey(e)
    document.addEventListener("cmd:open", this.onOpen)
    this.inputTarget.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("cmd:open", this.onOpen)
  }

  open() {
    const wrap = document.getElementById("cmdline_wrap")
    wrap.classList.remove("hidden")
    const runEl = document.querySelector("[id^='tool_run_']")
    if (runEl && this.hasRunIdTarget) this.runIdTarget.value = runEl.id.replace("tool_run_", "")
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  close() {
    document.getElementById("cmdline_wrap").classList.add("hidden")
    document.dispatchEvent(new Event("cmd:close"))
  }

  handleKey(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }
    if (event.key === "Tab") {
      event.preventDefault()
      this.complete()
      return
    }
    if (event.key === "ArrowUp") {
      event.preventDefault()
      if (this.history.length === 0) return
      this.historyIdx = Math.min(this.history.length - 1, this.historyIdx + 1)
      this.inputTarget.value = this.history[this.history.length - 1 - this.historyIdx] || ""
      return
    }
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.historyIdx = Math.max(-1, this.historyIdx - 1)
      this.inputTarget.value = this.historyIdx === -1 ? "" : this.history[this.history.length - 1 - this.historyIdx]
      return
    }
  }

  complete() {
    const val = this.inputTarget.value.replace(/^:/, "")
    const match = KNOWN.find(k => k.startsWith(val))
    if (match && match !== val) this.inputTarget.value = ":" + match + " "
  }

  submit(event) {
    const raw = this.inputTarget.value.trim().replace(/^:/, "")
    if (!raw) { event.preventDefault(); return }
    const head = raw.split(/\s+/)[0]

    // History
    this.history.push(raw)
    this.history = this.history.slice(-50)
    Prefs.set("cmd_history", this.history)
    this.historyIdx = -1

    if (CLIENT_ONLY.includes(head)) {
      event.preventDefault()
      this.dispatchClient(raw)
      this.inputTarget.value = ""
      return
    }
    // Else: form submits to /commands as turbo_stream (default behavior)
  }

  dispatchClient(raw) {
    const [head, ...rest] = raw.split(/\s+/)
    switch (head) {
      case "copy":
        document.dispatchEvent(new CustomEvent("yank:request", { detail: { target: rest[0] || "summary" } }))
        break
      case "q":
        document.dispatchEvent(new Event("result:clear"))
        break
      case "raw":
        document.querySelectorAll("[data-truncated]").forEach(el => { el.dataset.expanded = "true" })
        break
      case "tool":
        window.location = "/workbench?tool=" + encodeURIComponent(rest[0] || "")
        break
      case "target":
        const el = document.querySelector("[data-workbench-target='input']")
        if (el) el.value = rest.join(" ")
        break
      case "pin":
        const slots = Prefs.get("pinned", null) ||
          JSON.parse(document.querySelector("[data-default-slots]")?.dataset.defaultSlots || "[]")
        const slot = parseInt(rest[1], 10) - 1
        if (slot >= 0 && slot < 9 && rest[0]) {
          slots[slot] = rest[0]
          Prefs.set("pinned", slots)
          window.location.reload()
        }
        break
      case "expiring":
        window.location = "/workbench?view=history&filter=" + encodeURIComponent("severity>=warn expires<30d")
        break
      case "history":
        window.location = "/workbench?view=history" + (rest.length ? "&filter=" + encodeURIComponent(rest.join(" ")) : "")
        break
      case "help":
        if (rest[0] === "tour") {
          Prefs.remove("tour_done")
          document.dispatchEvent(new Event("tour:start"))
        } else {
          document.dispatchEvent(new Event("help:toggle"))
        }
        break
      case "set":
        if (rest[0] && rest[1] !== undefined) Prefs.set(rest[0], rest.slice(1).join(" "))
        break
    }
    this.close()
  }
}
