// app/javascript/controllers/node_config_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["versionSelect"]

  connect() {
    // Show compatibility warning for initially selected version
    this.toggleVersionWarning()
  }
  change(event) {
    const providerId = event.target.value
    const clusterId = event.target.dataset.clusterId
    const nodeId = this.element.dataset.nodeId
    const parentNodeId = this.element.dataset.parentNodeId

    if (providerId) {
      let url = `/clusters/${clusterId}/nodes/config_partial?provider_id=${providerId}`
      
      if (nodeId) {
        url += `&node_id=${nodeId}`
      }
      
      if (parentNodeId) {
        url += `&parent_node_id=${parentNodeId}`
      }
      
      // Store current form values before turbo replaces content
      const currentValues = this.getCurrentFormValues()
      
      fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest',
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      })
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }
        return response.text()
      })
      .then(html => {
        // Update the config partial frame
        const frame = document.getElementById("config_partial")
        if (frame) {
          frame.innerHTML = html
          
          // After the new content loads, restore any matching values
          setTimeout(() => {
            this.restoreFormValues(currentValues)
          }, 100)
        }
      })
      .catch(error => {
        console.error('Error loading config partial:', error)
        const frame = document.getElementById("config_partial")
        if (frame) {
          frame.innerHTML = '<div class="alert alert-danger">Error loading configuration options</div>'
        }
      })
    } else {
      const frame = document.getElementById("config_partial")
      if (frame) {
        frame.innerHTML = ""
      }
    }
  }

  versionChange(event) {
    this.toggleVersionWarning()
  }

  toggleVersionWarning() {
    // Hide all version warnings first
    const allWarnings = this.element.querySelectorAll('[data-version-id]')
    allWarnings.forEach(warning => {
      warning.style.display = 'none'
    })

    // Show warning for selected version if it has one
    const versionSelect = this.element.querySelector('[name*="database_type_version_id"]')
    if (versionSelect && versionSelect.value) {
      const warning = this.element.querySelector(`[data-version-id="${versionSelect.value}"]`)
      if (warning) {
        warning.style.display = 'block'
      }
    }
  }

  getCurrentFormValues() {
    const values = {}
    const configFrame = document.getElementById("config_partial")
    if (configFrame) {
      const inputs = configFrame.querySelectorAll('input, select, textarea')
      inputs.forEach(input => {
        if (input.name && input.value) {
          values[input.name] = input.value
        }
      })
    }
    return values
  }

  restoreFormValues(values) {
    const configFrame = document.getElementById("config_partial")
    if (configFrame) {
      Object.entries(values).forEach(([name, value]) => {
        const input = configFrame.querySelector(`[name="${name}"]`)
        if (input && !input.value) {
          input.value = value
          // Trigger change event for dynamic selects
          input.dispatchEvent(new Event('change', { bubbles: true }))
        }
      })
    }
  }
}
