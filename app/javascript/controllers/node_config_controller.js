// app/javascript/controllers/node_config_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
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
          'Accept': 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      .then(response => response.text())
      .then(html => {
        // Update the config partial frame
        document.getElementById("config_partial").innerHTML = html
        
        // After the new content loads, restore any matching values
        setTimeout(() => {
          this.restoreFormValues(currentValues)
        }, 100)
      })
      .catch(error => {
        console.error('Error loading config partial:', error)
        document.getElementById("config_partial").innerHTML = '<div class="alert alert-danger">Error loading configuration options</div>'
      })
    } else {
      document.getElementById("config_partial").innerHTML = ""
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
