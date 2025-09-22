import { Controller } from "@hotwired/stimulus"

// Simple test controller to debug ActionCable issues
export default class extends Controller {
  static values = { 
    nodeId: Number,
    clusterId: Number 
  }

  connect() {
    console.log("🔥 SIMPLE NodeStatus controller connected!")
    console.log("Values:", {
      nodeId: this.nodeIdValue,
      clusterId: this.clusterIdValue,
      hasNodeIdValue: this.hasNodeIdValue,
      hasClusterIdValue: this.hasClusterIdValue
    })
    
    // Test ActionCable availability
    console.log("ActionCable available:", typeof ActionCable !== 'undefined')
    console.log("createConsumer available:", typeof createConsumer !== 'undefined')
    
    if (typeof createConsumer !== 'undefined') {
      console.log("🚀 Attempting to create consumer...")
      try {
        this.consumer = createConsumer()
        console.log("✅ Consumer created:", this.consumer)
        
        console.log("🔌 Attempting to subscribe to NodeStatusChannel...")
        this.subscription = this.consumer.subscriptions.create(
          { channel: "NodeStatusChannel" },
          {
            connected: () => {
              console.log("✅ CONNECTED to NodeStatusChannel!")
            },
            disconnected: () => {
              console.log("❌ DISCONNECTED from NodeStatusChannel")
            },
            received: (data) => {
              console.log("📨 RECEIVED data:", data)
            },
            rejected: () => {
              console.error("❌ NodeStatusChannel subscription REJECTED")
            }
          }
        )
        
      } catch (error) {
        console.error("❌ Error setting up ActionCable:", error)
      }
    }
  }

  disconnect() {
    console.log("🔥 SIMPLE NodeStatus controller disconnecting")
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
  }
}
