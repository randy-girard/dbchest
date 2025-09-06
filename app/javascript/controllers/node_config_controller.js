// app/javascript/controllers/node_config_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  change(event) {
    const providerId = event.target.value
    const clusterId = event.target.dataset.clusterId
    const nodeId = this.element.dataset.nodeId

    if (providerId) {
      Turbo.visit(`/clusters/${clusterId}/nodes/config_partial?node_id=${nodeId}&provider_id=${providerId}`, { frame: "config_partial" })
    } else {
      document.getElementById("config_partial").innerHTML = ""
    }
  }
}
