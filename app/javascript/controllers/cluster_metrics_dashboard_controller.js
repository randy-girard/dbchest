import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = { 
    clusterId: String
  }
  
  static targets = [
    "clusterCpu", "clusterCpuBar",
    "clusterMemory", "clusterMemoryBar", 
    "clusterDisk", "clusterDiskBar",
    "healthyNodes", "connectionStatus",
    "nodesGrid"
  ]

  connect() {
    console.log("ClusterMetricsDashboard controller connected for cluster:", this.clusterIdValue)
    
    this.timeRange = "1h"
    this.consumer = null
    this.subscription = null
    this.nodeMetrics = new Map() // Store latest metrics for each node
    
    this.setupActionCable()
    this.startPeriodicRefresh()
  }

  disconnect() {
    console.log("ClusterMetricsDashboard controller disconnecting")
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
    }
  }

  setupActionCable() {
    try {
      this.consumer = createConsumer()
      
      this.subscription = this.consumer.subscriptions.create(
        {
          channel: "NodeMetricsChannel",
          cluster_id: this.clusterIdValue
        },
        {
          connected: () => {
            console.log("✅ Connected to NodeMetricsChannel for cluster")
            this.updateConnectionStatus("Connected", "success")
          },
          
          disconnected: () => {
            console.log("❌ Disconnected from NodeMetricsChannel")
            this.updateConnectionStatus("Disconnected", "danger")
          },
          
          received: (data) => {
            console.log("📥 Received cluster metrics data:", data)
            if (data.type === 'metrics_update' && data.cluster_id == this.clusterIdValue) {
              this.updateNodeMetrics(data.node_id, data.metrics)
              this.updateClusterMetrics()
              this.updateNodeCard(data.node_id, data.metrics)
            }
          }
        }
      )
    } catch (error) {
      console.error("❌ Error setting up ActionCable:", error)
      this.updateConnectionStatus("Connection Error", "danger")
    }
  }

  startPeriodicRefresh() {
    // Refresh cluster data every 30 seconds
    this.refreshInterval = setInterval(() => {
      this.refreshData()
    }, 30000)
  }

  updateNodeMetrics(nodeId, metrics) {
    this.nodeMetrics.set(nodeId, metrics)
  }

  updateClusterMetrics() {
    if (this.nodeMetrics.size === 0) return

    const allMetrics = Array.from(this.nodeMetrics.values())
    
    // Calculate cluster-wide averages
    const cpuValues = allMetrics.map(m => m.cpu.usage_percent).filter(v => v !== null)
    const memoryValues = allMetrics.map(m => m.memory.usage_percent).filter(v => v !== null)
    
    if (cpuValues.length > 0) {
      const avgCpu = (cpuValues.reduce((a, b) => a + b, 0) / cpuValues.length).toFixed(1)
      this.updateClusterCpu(avgCpu)
    }
    
    if (memoryValues.length > 0) {
      const avgMemory = (memoryValues.reduce((a, b) => a + b, 0) / memoryValues.length).toFixed(1)
      this.updateClusterMemory(avgMemory)
    }
    
    // Calculate total memory usage
    const totalMemoryMb = allMetrics.reduce((sum, m) => sum + (m.memory.total_mb || 0), 0)
    const usedMemoryMb = allMetrics.reduce((sum, m) => sum + (m.memory.used_mb || 0), 0)
    
    if (totalMemoryMb > 0) {
      const totalMemoryPercent = ((usedMemoryMb / totalMemoryMb) * 100).toFixed(1)
      this.updateClusterMemory(totalMemoryPercent)
    }
    
    // Calculate disk usage (root filesystem)
    const diskValues = allMetrics
      .map(m => m.disk && m.disk['/'] ? m.disk['/'].usage_percent : null)
      .filter(v => v !== null)
    
    if (diskValues.length > 0) {
      const avgDisk = (diskValues.reduce((a, b) => a + b, 0) / diskValues.length).toFixed(1)
      this.updateClusterDisk(avgDisk)
    }
    
    // Update health status
    this.updateHealthStatus(allMetrics)
  }

  updateClusterCpu(percentage) {
    if (this.hasClusterCpuTarget) {
      this.clusterCpuTarget.textContent = `${percentage}%`
    }
    if (this.hasClusterCpuBarTarget) {
      this.clusterCpuBarTarget.style.width = `${percentage}%`
      this.clusterCpuBarTarget.className = `progress-bar ${this.getProgressBarClass(percentage, 70, 85)}`
    }
  }

  updateClusterMemory(percentage) {
    if (this.hasClusterMemoryTarget) {
      this.clusterMemoryTarget.textContent = `${percentage}%`
    }
    if (this.hasClusterMemoryBarTarget) {
      this.clusterMemoryBarTarget.style.width = `${percentage}%`
      this.clusterMemoryBarTarget.className = `progress-bar bg-success ${this.getProgressBarClass(percentage, 75, 90)}`
    }
  }

  updateClusterDisk(percentage) {
    if (this.hasClusterDiskTarget) {
      this.clusterDiskTarget.textContent = `${percentage}%`
    }
    if (this.hasClusterDiskBarTarget) {
      this.clusterDiskBarTarget.style.width = `${percentage}%`
      this.clusterDiskBarTarget.className = `progress-bar bg-warning ${this.getProgressBarClass(percentage, 80, 90)}`
    }
  }

  updateHealthStatus(allMetrics) {
    let healthyCount = 0
    let warningCount = 0
    let criticalCount = 0
    
    allMetrics.forEach(metrics => {
      const status = metrics.health_status
      switch (status) {
        case 'healthy':
          healthyCount++
          break
        case 'warning':
          warningCount++
          break
        case 'critical':
          criticalCount++
          break
      }
    })
    
    if (this.hasHealthyNodesTarget) {
      this.healthyNodesTarget.textContent = `${healthyCount}/${allMetrics.length}`
    }
  }

  updateNodeCard(nodeId, metrics) {
    const nodeCard = this.nodesGridTarget.querySelector(`[data-node-id="${nodeId}"]`)
    if (!nodeCard) return
    
    // Update CPU
    const cpuElement = nodeCard.querySelector('.col-4:nth-child(1) strong')
    if (cpuElement) {
      cpuElement.textContent = `${metrics.cpu.usage_percent}%`
      cpuElement.className = `text-${this.getStatusColor(metrics.cpu.status)}`
    }
    
    // Update Memory
    const memoryElement = nodeCard.querySelector('.col-4:nth-child(2) strong')
    if (memoryElement) {
      memoryElement.textContent = `${metrics.memory.usage_percent}%`
      memoryElement.className = `text-${this.getStatusColor(metrics.memory.status)}`
    }
    
    // Update Disk
    const diskElement = nodeCard.querySelector('.col-4:nth-child(3) strong')
    if (diskElement && metrics.disk && metrics.disk['/']) {
      diskElement.textContent = `${metrics.disk['/'].usage_percent}%`
      diskElement.className = `text-${this.getStatusColor(this.getDiskStatus(metrics.disk['/'].usage_percent))}`
    }
    
    // Update card border based on overall health
    const card = nodeCard.querySelector('.card')
    if (card) {
      card.className = `card border-${this.getStatusColor(metrics.health_status)}`
    }
    
    // Update last update time
    const lastUpdateElement = nodeCard.querySelector('small.text-muted')
    if (lastUpdateElement) {
      lastUpdateElement.textContent = `Last update: just now`
    }
  }

  getDiskStatus(usage) {
    if (usage >= 90) return 'critical'
    if (usage >= 80) return 'warning'
    return 'healthy'
  }

  getStatusColor(status) {
    switch (status) {
      case 'healthy': return 'success'
      case 'warning': return 'warning'
      case 'critical': return 'danger'
      default: return 'secondary'
    }
  }

  getProgressBarClass(value, warningThreshold, criticalThreshold) {
    if (value >= criticalThreshold) return 'bg-danger'
    if (value >= warningThreshold) return 'bg-warning'
    return ''
  }

  updateConnectionStatus(status, type) {
    if (this.hasConnectionStatusTarget) {
      this.connectionStatusTarget.textContent = status
      this.connectionStatusTarget.className = `badge bg-${type}`
    }
  }

  // Action methods
  async refreshData() {
    console.log("Refreshing cluster dashboard data...")
    try {
      const response = await fetch(`/clusters/${this.clusterIdValue}/dashboard/live_status`)
      const data = await response.json()
      
      if (data.nodes) {
        // Update stored metrics for all nodes
        data.nodes.forEach(node => {
          if (node.latest_metrics) {
            this.updateNodeMetrics(node.id, node.latest_metrics)
            this.updateNodeCard(node.id, node.latest_metrics)
          }
        })
        
        // Recalculate cluster metrics
        this.updateClusterMetrics()
      }
    } catch (error) {
      console.error("Error refreshing cluster data:", error)
    }
  }

  changeTimeRange(event) {
    event.preventDefault()
    const range = event.target.dataset.range
    if (range) {
      this.timeRange = range
      console.log(`Changing time range to: ${range}`)
      this.refreshData()
    }
  }
}
