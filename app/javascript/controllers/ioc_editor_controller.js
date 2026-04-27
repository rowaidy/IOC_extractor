import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["total", "saveBar"]

  connect() {
    this.refreshCount()
  }

  deleteRow(event) {
    const row   = event.currentTarget.closest("tr")
    const tbody = row.closest("tbody")
    const card  = row.closest(".ioc-group-card")

    row.remove()

    if (tbody.querySelectorAll("tr").length === 0) {
      card.remove()
    }

    this.refreshCount()
    this.markDirty()
  }

  refreshCount() {
    const n = this.element.querySelectorAll("tbody tr").length
    if (this.hasTotalTarget) this.totalTarget.textContent = n
    const banner = document.getElementById("ioc-total-banner")
    if (banner) banner.textContent = n
  }

  markDirty() {
    if (this.hasSaveBarTarget) {
      this.saveBarTarget.classList.remove("d-none")
    }
  }
}
