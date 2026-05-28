import { Controller } from "@hotwired/stimulus"

// Mirrors lib/tool_harness/host_normalizer.rb — keep in sync.
// Three-branch structure: http(s):// → strip scheme then fall through,
// other :// scheme → return unchanged, otherwise → fall through to path strip.
function normalize(value, preservePath) {
  let s = String(value ?? "").trim()
  if (!s) return s

  const httpSchemeRx = /^https?:\/\//i
  if (httpSchemeRx.test(s)) {
    s = s.replace(httpSchemeRx, "")
  } else if (s.includes("://")) {
    return s
  }

  return preservePath ? s.replace(/\/+$/, "") : s.replace(/[\/?#][\s\S]*$/, "")
}

export default class extends Controller {
  static values = { preservePath: Boolean }

  connect() {
    this.normalizeNow = () => {
      const cleaned = normalize(this.element.value, this.preservePathValue)
      if (cleaned !== this.element.value) {
        this.element.value = cleaned
      }
    }
    // Normalize only on paste (the painful case) and on blur (catches typed
    // URLs before submit). Avoid `input` to not consume the user's keystrokes
    // mid-typing — e.g. typing the `/` in `http:/` would otherwise be eaten
    // by the path-strip regex before they can type the second slash.
    this.onPaste = () => setTimeout(this.normalizeNow, 0)
    this.element.addEventListener("paste", this.onPaste)
    this.element.addEventListener("blur", this.normalizeNow)
  }

  disconnect() {
    this.element.removeEventListener("paste", this.onPaste)
    this.element.removeEventListener("blur", this.normalizeNow)
  }
}
