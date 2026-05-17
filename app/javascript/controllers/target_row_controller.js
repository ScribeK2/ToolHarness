import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onRun   = () => this.element.querySelector("form")?.requestSubmit()
    this.onClear = () => {
      const panel = document.getElementById("result_panel")
      if (panel) panel.innerHTML = '<div class="text-mute">▸ Ready.  type a target, then Enter or :r</div>'
    }
    document.addEventListener("run:request",   this.onRun)
    document.addEventListener("result:clear",  this.onClear)
  }
  disconnect() {
    document.removeEventListener("run:request",   this.onRun)
    document.removeEventListener("result:clear",  this.onClear)
  }
}
