import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Development console for monitoring background jobs via browser console
export default class extends Controller {
  connect() {
    // Only run in development
    if (typeof Rails !== 'undefined' && Rails.env !== 'development') {
      return
    }

    console.log("🖥️  Development Console: Connecting to background job monitoring...")
    console.log("📡 All service logs and background job messages will appear in this console")
    
    // Connect to development console channel
    this.initializeConsoleChannel()
  }



  initializeConsoleChannel() {
    try {
      this.consumer = createConsumer()
      
      this.subscription = this.consumer.subscriptions.create(
        "DevelopmentConsoleChannel",
        {
          connected: () => {
            this.logMessage("Connected to development console", "system")
          },
          
          disconnected: () => {
            this.logMessage("Disconnected from development console", "system")
          },
          
          received: (data) => {
            this.handleConsoleMessage(data)
          }
        }
      )
    } catch (error) {
      console.error("Failed to connect to development console:", error)
    }
  }

  handleConsoleMessage(data) {
    const { event_type, timestamp } = data
    
    switch (event_type) {
      case 'node_status_update':
        this.logNodeStatusUpdate(data)
        break
      case 'ansible_task':
        this.logAnsibleTask(data)
        break
      case 'job_message':
        this.logJobMessage(data)
        break
      case 'terraform_log':
        this.logTerraformMessage(data)
        break
      default:
        this.logMessage(`${timestamp} Unknown event: ${JSON.stringify(data)}`, "unknown")
    }
  }

  logNodeStatusUpdate(data) {
    const { timestamp, node_name, status, message } = data
    this.logMessage(
      `${timestamp} NODE[${node_name}] ${status.toUpperCase()}${message ? ': ' + message : ''}`,
      "node"
    )
  }

  logAnsibleTask(data) {
    const { timestamp, node_id, task_name, status, details, playbook } = data
    let message = `${timestamp} ANSIBLE[${node_id}] ${playbook} - ${task_name}`
    if (details && details.trim()) {
      message += `\n    ${details.replace(/\n/g, '\n    ')}`
    }
    this.logMessage(message, "ansible")
  }

  logJobMessage(data) {
    const { timestamp, job_name, message, level, primary_node_id, replica_node_id, replica_ip } = data
    const nodeInfo = replica_ip ? `[${primary_node_id}→${replica_node_id}@${replica_ip}]` : `[${primary_node_id || 'unknown'}]`
    this.logMessage(
      `${timestamp} JOB${nodeInfo} ${job_name}: ${message}`,
      level === 'error' ? 'job_error' : 'job'
    )
  }

  logTerraformMessage(data) {
    const { timestamp, message } = data
    this.logMessage(`${timestamp} TERRAFORM: ${message}`, "terraform")
  }

  logMessage(message, type, color = null) {
    // Use browser's built-in console with appropriate styling
    const prefix = `🖥️ DBChest:`
    
    switch (type) {
      case 'node':
        console.log(`%c${prefix} ${message}`, 'color: #00aaff; font-weight: bold;')
        break
      case 'ansible':
        console.log(`%c${prefix} ${message}`, 'color: #ff6600; font-weight: bold;')
        break
      case 'terraform':
        console.log(`%c${prefix} ${message}`, 'color: #7c3aed; font-weight: bold;')
        break
      case 'job':
        console.log(`%c${prefix} ${message}`, 'color: #9d4edd; font-weight: bold;')
        break
      case 'job_error':
        console.error(`%c${prefix} ${message}`, 'color: #e63946; font-weight: bold;')
        break
      case 'system':
        console.log(`%c${prefix} ${message}`, 'color: #888888;')
        break
      default:
        console.log(`${prefix} ${message}`)
        break
    }
  }



  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    
    console.log("🖥️ DBChest: Development console disconnected")
  }
}
