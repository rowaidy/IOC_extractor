import { Controller } from "@hotwired/stimulus"

const STEPS = [
  { label: "Reading document",        pct: 15,  ms: 800  },
  { label: "Extracting text",         pct: 35,  ms: 2500 },
  { label: "Detecting IOC indicators",pct: 65,  ms: 2000 },
  { label: "Building OpenIOC file",   pct: 88,  ms: 1500 },
  { label: "Finalising",              pct: 97,  ms: 800  },
]

export default class extends Controller {
  static targets = ["input", "filename", "zone"]

  connect() {
    this.zoneTarget.addEventListener("dragover",  this.onDragOver.bind(this))
    this.zoneTarget.addEventListener("dragleave", this.onDragLeave.bind(this))
    this.zoneTarget.addEventListener("drop",      this.onDrop.bind(this))
    this.element.addEventListener("submit",       this.onSubmit.bind(this))
  }

  fileSelected() {
    const file = this.inputTarget.files[0]
    if (file) {
      this.filenameTarget.textContent = file.name
      this.zoneTarget.classList.add("file-chosen")
    }
  }

  onDragOver(e) {
    e.preventDefault()
    this.zoneTarget.classList.add("drag-over")
  }

  onDragLeave() {
    this.zoneTarget.classList.remove("drag-over")
  }

  onDrop(e) {
    e.preventDefault()
    this.zoneTarget.classList.remove("drag-over")
    const file = e.dataTransfer.files[0]
    if (!file) return
    const dt = new DataTransfer()
    dt.items.add(file)
    this.inputTarget.files = dt.files
    this.filenameTarget.textContent = file.name
    this.zoneTarget.classList.add("file-chosen")
  }

  onSubmit(e) {
    if (!this.inputTarget.files.length) return
    this.showOverlay()
  }

  // ── Overlay ────────────────────────────────────────────────────────────────

  showOverlay() {
    const overlay = document.getElementById("processing-overlay")
    if (!overlay) return

    overlay.classList.remove("d-none")
    this.bar   = overlay.querySelector(".processing-bar")
    this.items = Array.from(overlay.querySelectorAll(".processing-steps li"))

    this.currentStep = 0
    this.advanceStep()
  }

  advanceStep() {
    if (this.currentStep >= STEPS.length) return

    const step = STEPS[this.currentStep]

    // Mark previous step done
    if (this.currentStep > 0) {
      this.items[this.currentStep - 1].classList.remove("step-active")
      this.items[this.currentStep - 1].classList.add("step-done")
    }

    // Activate current step
    this.items[this.currentStep].classList.add("step-active")

    // Animate progress bar
    if (this.bar) this.bar.style.width = step.pct + "%"

    this.currentStep++
    this.timer = setTimeout(() => this.advanceStep(), step.ms)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
