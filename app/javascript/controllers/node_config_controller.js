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
      
      Turbo.visit(url, { frame: "config_partial" })
    } else {
      document.getElementById("config_partial").innerHTML = ""
    }
  }
}
