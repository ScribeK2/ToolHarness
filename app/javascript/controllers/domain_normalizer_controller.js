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
    this.onInput = () => {
      const cleaned = normalize(this.element.value, this.preservePathValue)
      if (cleaned !== this.element.value) {
        this.element.value = cleaned
      }
    }
    this.element.addEventListener("input", this.onInput)
  }

  disconnect() {
    this.element.removeEventListener("input", this.onInput)
  }
}
