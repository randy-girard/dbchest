// app/javascript/controllers/provider_config_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  change(event) {
    const type = event.target.value
    if (type) {
      Turbo.visit(`/providers/config_partial?type=${type}`, { frame: "config_partial" })
    } else {
      Turbo.clearFrame("config_partial")
    }
  }
}
