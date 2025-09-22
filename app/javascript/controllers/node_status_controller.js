import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="node-status"
export default class extends Controller {
  static targets = ["status", "message"]
  static values = { 
    nodeId: Number,
    clusterId: Number 
  }

  connect() {
    console.log("🎯 NodeStatus controller CONNECTING with values:", {
      nodeId: this.nodeIdValue,
      clusterId: this.clusterIdValue,
      hasNodeIdValue: this.hasNodeIdValue,
      hasClusterIdValue: this.hasClusterIdValue,
      element: this.element
    })
    
    // Also check what node status elements are available on this page
    const statusElements = document.querySelectorAll('[data-node-status]')
    console.log(`Found ${statusElements.length} node status elements on page:`, 
      Array.from(statusElements).map(el => ({
        nodeId: el.getAttribute('data-node-status'),
        element: el
      }))
    )
    
    // Wait a moment for imports to load, then try ActionCable
    setTimeout(() => {
      this.initializeActionCable()
    }, 100)
  }

  initializeActionCable() {
    console.log("🚀 Initializing ActionCable...")
    // Check if ActionCable is available
    if (typeof ActionCable === 'undefined' && typeof createConsumer === 'undefined') {
      console.error("❌ ActionCable not available! Using polling fallback")
      this.actionCableAvailable = false
      this.startPolling() // Use polling as fallback
      return
    }
    
    try {
      // Use the global createConsumer function
      this.consumer = createConsumer()
      
      console.log("✅ ActionCable consumer created:", this.consumer)
      this.actionCableAvailable = true
      this.subscribeToUpdates()
      
      // Don't use polling when ActionCable is working to avoid conflicts
      console.log("✅ ActionCable is working, skipping polling fallback")
    } catch (error) {
      console.error("❌ Error setting up ActionCable:", error)
      this.actionCableAvailable = false
      this.startPolling() // Use polling as fallback
    }
  }

  disconnect() {
    console.log("NodeStatus controller disconnecting")
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
    this.stopPolling()
  }

  subscribeToUpdates() {
    // Prepare subscription parameters
    const channelParams = {}
    if (this.hasNodeIdValue) {
      channelParams.node_id = this.nodeIdValue
    }
    if (this.hasClusterIdValue) {
      channelParams.cluster_id = this.clusterIdValue
    }

    console.log("Creating NodeStatusChannel subscription with params:", channelParams)

    this.subscription = this.consumer.subscriptions.create(
      { channel: "NodeStatusChannel", ...channelParams },
      {
        connected: () => {
          console.log("Connected to NodeStatusChannel with params:", channelParams)
          
          // Subscribe to all nodes found on this page
          setTimeout(() => {
            // Subscribe to main node if available
            if (this.hasNodeIdValue) {
              console.log(`🎯 Subscribing to main node: ${this.nodeIdValue}`)
              this.subscription.perform("subscribe_to_node", { node_id: this.nodeIdValue })
            }
            
            // Subscribe to cluster if available
            if (this.hasClusterIdValue) {
              console.log(`🌐 Subscribing to cluster: ${this.clusterIdValue}`)
              this.subscription.perform("subscribe_to_cluster", { cluster_id: this.clusterIdValue })
            }
            
            // Find and subscribe to ALL nodes on the page (including replicas)
            const allNodeElements = document.querySelectorAll('[data-node-status]')
            const nodeIds = Array.from(allNodeElements).map(el => el.getAttribute('data-node-status'))
            const uniqueNodeIds = [...new Set(nodeIds)] // Remove duplicates
            
            console.log(`🔍 Found ${uniqueNodeIds.length} unique nodes on page:`, uniqueNodeIds)
            
            uniqueNodeIds.forEach(nodeId => {
              if (nodeId && nodeId !== this.nodeIdValue?.toString()) {
                console.log(`📡 Also subscribing to additional node: ${nodeId}`)
                this.subscription.perform("subscribe_to_node", { node_id: parseInt(nodeId) })
              }
            })
          }, 100)
        },

        disconnected: () => {
          console.log("Disconnected from NodeStatusChannel")
          // Don't auto-reconnect to avoid multiple subscriptions
          // Let polling handle updates if ActionCable fails
          if (!this.pollingInterval) {
            console.log("ActionCable disconnected, starting polling fallback")
            this.startPolling()
          }
        },

        received: (data) => {
          console.log("✅ Received node status update:", data)
          
          // Check if this is for main node or replica
          const isMainNode = this.hasNodeIdValue && data.id === this.nodeIdValue
          const nodeType = isMainNode ? "MAIN NODE" : "REPLICA NODE"
          console.log(`🎯 Processing ${nodeType} update for node ${data.id} (${data.name})`)
          
          console.log("🔍 Available node elements on page:", 
            Array.from(document.querySelectorAll('[data-node-status]')).map(el => ({
              nodeId: el.getAttribute('data-node-status'),
              currentText: el.textContent.trim()
            }))
          )
          
          this.updateNodeStatus(data)
        },

        rejected: () => {
          console.error("❌ NodeStatusChannel subscription rejected")
          // Don't auto-retry to avoid subscription conflicts
          // Let polling handle updates if ActionCable is rejected
          if (!this.pollingInterval) {
            console.log("ActionCable rejected, starting polling fallback")
            this.startPolling()
          }
        }
      }
    )
  }

  updateNodeStatus(data) {
    const nodeId = data.id
    console.log(`Updating status for node ${nodeId}:`, data)
    
    // Update all status badges for this node
    const statusElements = document.querySelectorAll(`[data-node-status="${nodeId}"]`)
    console.log(`Found ${statusElements.length} status elements for node ${nodeId}`)
    
    // Debug: Show all available status elements on page
    const allStatusElements = document.querySelectorAll('[data-node-status]')
    console.log(`Debug: All ${allStatusElements.length} status elements on page:`, 
      Array.from(allStatusElements).map(el => ({
        nodeId: el.getAttribute('data-node-status'),
        text: el.textContent.trim(),
        classes: el.className,
        element: el
      }))
    )
    
    if (statusElements.length === 0) {
      console.warn(`No status elements found for node ${nodeId}. Available elements:`, 
        Array.from(document.querySelectorAll('[data-node-status]')).map(el => el.getAttribute('data-node-status')))
    }
    
    statusElements.forEach(element => {
      console.log(`Updating element:`, element)
      element.textContent = data.status_display
      // Remove old badge classes and add new one
      element.className = element.className.replace(/bg-\w+/g, '')
      element.classList.add(data.status_badge_class)
      
      // Add visual flash effect to indicate update
      element.style.transition = 'all 0.3s ease'
      element.style.transform = 'scale(1.05)'
      setTimeout(() => {
        element.style.transform = 'scale(1)'
      }, 300)
    })
    
    // Update all status message areas for this node
    const messageElements = document.querySelectorAll(`[data-node-status-message="${nodeId}"]`)
    console.log(`Found ${messageElements.length} message elements for node ${nodeId}`)
    
    messageElements.forEach(element => {
      if (data.message) {
        // For the alert box in show view
        if (element.classList.contains('alert')) {
          element.style.display = 'block'
          const messageText = element.querySelector('.status-message-text')
          if (messageText) {
            messageText.textContent = data.message
          }
        } else {
          // For simple message divs in index view
          element.textContent = data.message
          element.style.display = 'block'
        }
      } else {
        // Hide message if no message
        if (element.classList.contains('alert')) {
          element.style.display = 'none'
        } else {
          element.style.display = 'none'
        }
      }
    })

    // Handle special status states
    this.handleSpecialStatuses(data)

    // Show a toast notification for status changes
    this.showNotification(data)
  }

  handleSpecialStatuses(data) {
    const nodeId = data.id
    
    // Handle destroying status - disable buttons
    if (data.status === 'destroying') {
      this.disableNodeButtons(nodeId)
    }
    
    // Handle destroyed status - remove the node row
    if (data.status === 'destroyed') {
      this.removeNodeFromTable(nodeId)
    }
    
    // Handle error status - highlight the node and stop polling for this node
    if (data.status === 'error') {
      console.log(`Node ${nodeId} is in error state: ${data.message}`)
    }
  }

  disableNodeButtons(nodeId) {
    // Find the table row for this node
    const nodeRow = document.querySelector(`[data-node-row-id="${nodeId}"]`)
    if (nodeRow) {
      // Disable all buttons in the row
      const buttons = nodeRow.querySelectorAll('button, .btn')
      buttons.forEach(button => {
        button.disabled = true
        button.classList.add('opacity-50')
      })
      
      // Disable dropdown toggles
      const dropdowns = nodeRow.querySelectorAll('[data-bs-toggle="dropdown"]')
      dropdowns.forEach(dropdown => {
        dropdown.disabled = true
        dropdown.classList.add('opacity-50')
      })
      
      console.log(`Disabled ${buttons.length} buttons for node ${nodeId}`)
    }
  }



  removeNodeFromTable(nodeId) {
    // Find the container for this node (table row or card)
    const nodeContainer = document.querySelector(`[data-node-row-id="${nodeId}"]`)
    if (nodeContainer) {
      // Add fade out animation
      nodeContainer.style.transition = 'opacity 0.5s ease, transform 0.5s ease'
      nodeContainer.style.opacity = '0.5'
      nodeContainer.style.transform = 'scale(0.95)'
      
      // Remove the container after animation
      setTimeout(() => {
        nodeContainer.style.opacity = '0'
        setTimeout(() => {
          nodeContainer.remove()
          console.log(`Removed node container ${nodeId}`)
          
          // Check if we need to refresh or show empty state
          const table = nodeContainer.closest('table')
          const cardGrid = nodeContainer.closest('.row-cards')
          
          if (table) {
            const tbody = table.querySelector('tbody')
            if (tbody && tbody.children.length === 0) {
              // Table is empty, refresh to show empty state
              window.location.reload()
            }
          } else if (cardGrid) {
            // Check if card grid is empty
            const remainingCards = cardGrid.querySelectorAll('[data-node-row-id]')
            if (remainingCards.length === 0) {
              // Card grid is empty, refresh to show empty state
              window.location.reload()
            }
          }
        }, 300)
      }, 200)
    }
  }

  showNotification(data) {
    // Create a simple toast notification
    const toast = document.createElement('div')
    toast.className = 'alert alert-info position-fixed top-0 end-0 m-3'
    toast.style.zIndex = '9999'
    toast.style.minWidth = '300px'
    toast.innerHTML = `
      <div class="d-flex">
        <div>
          <svg xmlns="http://www.w3.org/2000/svg" class="icon alert-icon" width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round">
            <path stroke="none" d="M0 0h24v24H0z" fill="none"/>
            <circle cx="12" cy="12" r="9"/>
            <line x1="12" y1="8" x2="12.01" y2="8"/>
            <polyline points="11,12 12,12 12,16 13,16"/>
          </svg>
        </div>
        <div>
          <h4 class="alert-title">${data.name}</h4>
          <div class="text-muted">Status: ${data.status_display}</div>
          ${data.message ? `<div class="text-muted">${data.message}</div>` : ''}
        </div>
        <button type="button" class="btn-close ms-auto" data-bs-dismiss="alert"></button>
      </div>
    `

    document.body.appendChild(toast)

    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (toast.parentNode) {
        toast.remove()
      }
    }, 5000)
  }

  startPolling() {
    // If ActionCable isn't available, poll more frequently
    const interval = this.actionCableAvailable === false ? 2000 : 5000
    
    // Only poll if we have active nodes (not in 'active' or 'error' state) or ActionCable isn't working
    const hasActiveNodes = this.hasNodesInTransition()
    if (hasActiveNodes || this.actionCableAvailable === false) {
      console.log(`🔄 Starting polling every ${interval}ms (ActionCable available: ${this.actionCableAvailable !== false})`)
      this.pollingInterval = setInterval(() => {
        this.checkNodeStatus()
      }, interval)
    }
  }

  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
      this.pollingInterval = null
    }
  }

  hasNodesInTransition() {
    const statusElements = document.querySelectorAll('[data-node-status]')
    for (let element of statusElements) {
      const classes = element.className
      if (classes.includes('bg-warning') || classes.includes('bg-info')) {
        return true
      }
    }
    return false
  }

  async checkNodeStatus() {
    // Simple status check for nodes that might be transitioning
    if (!this.hasNodesInTransition()) {
      this.stopPolling()
      return
    }

    // If ActionCable isn't working, poll the status API
    if (this.hasNodeIdValue) {
      try {
        console.log("📡 Polling node status via API...")
        const response = await fetch(`/nodes/${this.nodeIdValue}/status`, {
          headers: {
            'Accept': 'application/json'
          }
        })
        
        if (response.ok) {
          const data = await response.json()
          console.log("📥 Received status via polling:", data)
          this.updateNodeStatus(data)
        }
      } catch (error) {
        console.warn("⚠️ Polling failed:", error)
      }
    } else {
      console.log("⏳ Polling for node status changes...")
    }
  }

  // Test method that can be called from browser console
  testConnection() {
    console.log("=== Testing ActionCable connection ===")
    console.log("Consumer:", this.consumer)
    console.log("Subscription:", this.subscription)
    console.log("Connected:", this.subscription?.identifier)
    console.log("Node ID:", this.hasNodeIdValue ? this.nodeIdValue : 'None')
    console.log("Cluster ID:", this.hasClusterIdValue ? this.clusterIdValue : 'None')
    
    // Try to send a test message
    if (this.subscription) {
      console.log("Sending test subscription requests...")
      if (this.hasNodeIdValue) {
        this.subscription.perform("subscribe_to_node", { node_id: this.nodeIdValue })
      }
      if (this.hasClusterIdValue) {
        this.subscription.perform("subscribe_to_cluster", { cluster_id: this.clusterIdValue })
      }
    } else {
      console.error("No subscription available!")
    }
  }

  // Test method to manually trigger a status update
  async testBroadcast() {
    // If we have a specific node ID, test that node
    if (this.hasNodeIdValue) {
      console.log(`Testing broadcast for specific node ${this.nodeIdValue}...`)
      await this.testNodeBroadcast(this.nodeIdValue)
      return
    }

    // If we only have cluster ID, find nodes on this page to test
    if (this.hasClusterIdValue) {
      console.log(`Testing broadcast for cluster ${this.clusterIdValue}...`)
      
      const statusElements = document.querySelectorAll('[data-node-status]')
      if (statusElements.length === 0) {
        console.error("No nodes found on this page to test")
        return
      }
      
      // Test the first node found on the page
      const firstNodeId = statusElements[0].getAttribute('data-node-status')
      console.log(`Found ${statusElements.length} nodes on page, testing first node: ${firstNodeId}`)
      await this.testNodeBroadcast(firstNodeId)
      return
    }
    
    console.error("No node ID or cluster ID available for testing")
  }
  
  async testNodeBroadcast(nodeId) {
    console.log(`Testing broadcast for node ${nodeId}...`)
    
    try {
      const response = await fetch(`/nodes/${nodeId}/status`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        console.log("Current node status from API:", data)
        
        // Simulate receiving the data via ActionCable
        console.log("Simulating ActionCable received data...")
        this.updateNodeStatus(data)
      } else {
        console.error(`HTTP error! status: ${response.status}`)
      }
    } catch (error) {
      console.error("Error testing broadcast:", error)
    }
  }
}
