import { Controller } from "@hotwired/stimulus"

const TYPE_META = {
  sha512:        { label: "SHA-512",      group: "hash",       color: "secondary" },
  sha256:        { label: "SHA-256",      group: "hash",       color: "success"   },
  sha1:          { label: "SHA-1",        group: "hash",       color: "warning"   },
  md5:           { label: "MD5",          group: "hash",       color: "info"      },
  ipv4:          { label: "IPv4",         group: "network",    color: "primary"   },
  ipv6:          { label: "IPv6",         group: "network",    color: "primary"   },
  url:           { label: "URL",          group: "network",    color: "danger"    },
  email:         { label: "Email",        group: "network",    color: "success"   },
  domain:        { label: "Domain",       group: "network",    color: "warning"   },
  filepath_win:  { label: "Windows Path", group: "filesystem", color: "secondary" },
  filepath_unix: { label: "Unix Path",    group: "filesystem", color: "secondary" },
  registry_key:  { label: "Registry Key", group: "registry",   color: "danger"    },
  mutex:         { label: "Mutex",        group: "process",    color: "info"      },
  service_name:  { label: "Service Name", group: "process",    color: "info"      },
}

const GROUP_META = {
  hash:       { label: "File Hashes",     icon: "bi-hash",     color: "info"    },
  network:    { label: "Network",         icon: "bi-globe",    color: "primary" },
  filesystem: { label: "File System",     icon: "bi-folder2",  color: "warning" },
  registry:   { label: "Registry",        icon: "bi-database", color: "danger"  },
  process:    { label: "Process / Mutex", icon: "bi-cpu",      color: "success" },
}

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

  deleteGroup(event) {
    const card = event.currentTarget.closest(".ioc-group-card")
    if (!card) return
    card.remove()
    this.refreshCount()
    this.markDirty()
  }

  confirmAdd(event) {
    event.preventDefault()

    const valueInput = document.getElementById("add-ioc-value")
    const typeSelect = document.getElementById("add-ioc-type")
    const value      = valueInput.value.trim()
    const type       = typeSelect.value

    if (!value) {
      valueInput.classList.add("is-invalid")
      valueInput.focus()
      return
    }
    valueInput.classList.remove("is-invalid")

    const meta     = TYPE_META[type]
    const groupKey = meta.group

    let card = this.element.querySelector(`.ioc-group-card[data-group="${groupKey}"]`)
    if (!card) {
      card = this._buildGroupCard(groupKey)
      const anchor = document.getElementById("ioc-group-anchor")
      anchor.insertAdjacentElement("beforebegin", card)
    }

    card.querySelector("tbody").insertAdjacentHTML("beforeend", this._buildRow(value, type, meta))

    // Dismiss modal via Bootstrap global
    const modalEl = document.getElementById("add-indicator-modal")
    window.bootstrap?.Modal?.getInstance(modalEl)?.hide()

    valueInput.value = ""
    typeSelect.selectedIndex = 0

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

  _buildRow(value, type, meta) {
    const escaped = value.replace(/&/g,"&amp;").replace(/"/g,"&quot;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
    return `<tr>
      <td class="ps-3 text-muted">+</td>
      <td>
        <input type="text" name="entries[][value]" value="${escaped}"
               class="form-control form-control-sm font-monospace border-0 bg-transparent px-0"
               style="min-width:200px;"
               data-action="change->ioc-editor#markDirty">
        <input type="hidden" name="entries[][type]" value="${type}">
      </td>
      <td><span class="badge text-bg-${meta.color}">${meta.label}</span></td>
      <td class="pe-2 text-end">
        <button type="button" class="btn btn-link btn-sm text-danger p-0" title="Delete"
                data-action="click->ioc-editor#deleteRow">
          <i class="bi bi-trash3"></i>
        </button>
      </td>
    </tr>`
  }

  _buildGroupCard(groupKey) {
    const g    = GROUP_META[groupKey] || { label: groupKey, icon: "bi-tag", color: "secondary" }
    const card = document.createElement("div")
    card.className = "card border-0 shadow-sm mb-4 ioc-group-card"
    card.dataset.group = groupKey
    card.innerHTML = `
      <div class="card-header bg-dark text-white d-flex align-items-center justify-content-between">
        <span><i class="bi ${g.icon} text-${g.color} me-2"></i><strong>${g.label}</strong></span>
        <div class="d-flex align-items-center gap-2">
          <span class="badge bg-${g.color} text-dark">0</span>
          <button type="button" class="btn btn-sm btn-outline-danger py-0 px-2"
                  title="Delete all in this group"
                  data-action="click->ioc-editor#deleteGroup">
            <i class="bi bi-trash3 me-1"></i>Delete all
          </button>
        </div>
      </div>
      <div class="card-body p-0">
        <div class="table-responsive" style="max-height:400px;overflow-y:auto;">
          <table class="table table-sm table-hover mb-0 align-middle">
            <thead class="table-light sticky-top">
              <tr>
                <th class="ps-3" style="width:2.5rem;">#</th>
                <th>Indicator Value</th>
                <th style="width:9rem;">Type</th>
                <th class="pe-2" style="width:3rem;"></th>
              </tr>
            </thead>
            <tbody class="font-monospace small"></tbody>
          </table>
        </div>
      </div>`
    return card
  }
}
