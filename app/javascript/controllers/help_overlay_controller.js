import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onToggle = () => this.toggle()
    this.onKey = (e) => { if (e.key === "Escape" && !this.element.classList.contains("hidden")) this.close() }
    document.addEventListener("help:toggle", this.onToggle)
    document.addEventListener("keydown", this.onKey)
  }
  disconnect() {
    document.removeEventListener("help:toggle", this.onToggle)
    document.removeEventListener("keydown", this.onKey)
  }
  toggle() { this.element.classList.toggle("hidden") }
  close()  { this.element.classList.add("hidden") }
}
