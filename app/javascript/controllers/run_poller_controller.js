import { Controller } from "@hotwired/stimulus"

// Fallback for the broadcast race: a run that finishes before the browser's
// Turbo Stream subscription connects gets its completion broadcast dropped
// (Turbo Streams have no replay), leaving the spinner up forever. While the
// pending/processing markup is on screen, poll the run's current state; the
// server answers 204 until the run is terminal, then a replace stream that
// swaps in the result. Terminal markup carries no poller, so polling stops
// the moment the result lands — via either the broadcast or a poll.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 1000 }
  }

  connect() {
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" }
      })
      if (response.status === 404) { clearInterval(this.timer); return }
      if (!response.ok || response.status === 204) return
      window.Turbo.renderStreamMessage(await response.text())
    } catch {
      // Transient network hiccup — keep polling.
    }
  }
}
