import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = { 
    nodeId: String,
    clusterId: String
  }
  
  static targets = [
    "cpuUsage", "cpuProgressBar", "cpuChart",
    "memoryUsage", "memoryProgressBar", "memoryChart", 
    "diskUsage", "diskProgressBar", "diskChart",
    "uptime", "healthStatus", "loadChart",
    "networkStats", "lastUpdate", "connectionStatus",
    "alertsContainer", "alertsList"
  ]

  connect() {
    console.log("NodeMetricsDashboard controller connected for node:", this.nodeIdValue)

    this.timeRange = "1h"
    this.charts = {}
    this.consumer = null
    this.subscription = null

    // Wait a bit for Chart.js to load, then initialize
    setTimeout(() => {
      if (typeof Chart !== 'undefined') {
        console.log("✅ Chart.js loaded successfully")
        this.initializeCharts()
        this.loadInitialData()
        this.setupActionCable()
      } else {
        console.error("❌ Chart.js not loaded after timeout")
        this.connectionStatusTarget.textContent = "Chart.js not available"
        this.connectionStatusTarget.className = "badge bg-danger"
      }
    }, 100)
  }

  disconnect() {
    console.log("NodeMetricsDashboard controller disconnecting")
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
    
    // Destroy charts
    Object.values(this.charts).forEach(chart => {
      if (chart) chart.destroy()
    })
  }

  setupActionCable() {
    try {
      this.consumer = createConsumer()
      
      this.subscription = this.consumer.subscriptions.create(
        {
          channel: "NodeMetricsChannel",
          node_id: this.nodeIdValue,
          cluster_id: this.clusterIdValue
        },
        {
          connected: () => {
            console.log("✅ Connected to NodeMetricsChannel")
            this.updateConnectionStatus("Connected", "success")
          },
          
          disconnected: () => {
            console.log("❌ Disconnected from NodeMetricsChannel")
            this.updateConnectionStatus("Disconnected", "danger")
          },
          
          received: (data) => {
            console.log("📥 Received metrics data:", data)
            if (data.type === 'metrics_update' && data.node_id == this.nodeIdValue) {
              console.log("🎯 Processing metrics for node:", this.nodeIdValue)
              this.updateMetricsDisplay(data.metrics)
              this.updateCharts(data.metrics)
            } else {
              console.log("⏭️ Skipping metrics - node mismatch or wrong type:", {
                received_node: data.node_id,
                expected_node: this.nodeIdValue,
                type: data.type
              })
            }
          }
        }
      )
    } catch (error) {
      console.error("❌ Error setting up ActionCable:", error)
      this.updateConnectionStatus("Connection Error", "danger")
    }
  }

  initializeCharts() {
    console.log("🎨 Initializing charts...")
    console.log("📊 Chart.js version:", Chart.version)

    const chartOptions = {
      responsive: true,
      maintainAspectRatio: false,
      animation: {
        duration: 0 // Disable animations for real-time updates
      },
      scales: {
        x: {
          type: 'linear',
          position: 'bottom',
          ticks: {
            callback: function(value) {
              // Convert timestamp to readable time
              const date = new Date(value)
              return date.toLocaleTimeString('en-US', {
                hour12: false,
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
              })
            },
            maxTicksLimit: 8
          },
          title: {
            display: true,
            text: 'Time'
          }
        },
        y: {
          beginAtZero: true
        }
      },
      plugins: {
        legend: {
          display: false
        },
        tooltip: {
          callbacks: {
            title: function(context) {
              // Format tooltip title with readable timestamp
              const timestamp = context[0].parsed.x
              const date = new Date(timestamp)
              return date.toLocaleString('en-US', {
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit',
                hour12: false
              })
            }
          }
        }
      }
    }

    // CPU Chart
    console.log("🖥️ Creating CPU chart...")
    this.charts.cpu = new Chart(this.cpuChartTarget, {
      type: 'line',
      data: {
        datasets: [{
          label: 'CPU Usage (%)',
          data: [],
          borderColor: 'rgb(54, 162, 235)',
          backgroundColor: 'rgba(54, 162, 235, 0.1)',
          tension: 0.1
        }]
      },
      options: {
        ...chartOptions,
        scales: {
          ...chartOptions.scales,
          y: { ...chartOptions.scales.y, max: 100 }
        }
      }
    })

    // Memory Chart
    this.charts.memory = new Chart(this.memoryChartTarget, {
      type: 'line',
      data: {
        datasets: [{
          label: 'Memory Usage (%)',
          data: [],
          borderColor: 'rgb(75, 192, 192)',
          backgroundColor: 'rgba(75, 192, 192, 0.1)',
          tension: 0.1
        }]
      },
      options: {
        ...chartOptions,
        scales: {
          ...chartOptions.scales,
          y: { ...chartOptions.scales.y, max: 100 }
        }
      }
    })

    // Load Average Chart
    this.charts.load = new Chart(this.loadChartTarget, {
      type: 'line',
      data: {
        datasets: [
          {
            label: '1 min',
            data: [],
            borderColor: 'rgb(255, 99, 132)',
            backgroundColor: 'rgba(255, 99, 132, 0.1)',
            tension: 0.1
          },
          {
            label: '5 min',
            data: [],
            borderColor: 'rgb(255, 205, 86)',
            backgroundColor: 'rgba(255, 205, 86, 0.1)',
            tension: 0.1
          },
          {
            label: '15 min',
            data: [],
            borderColor: 'rgb(153, 102, 255)',
            backgroundColor: 'rgba(153, 102, 255, 0.1)',
            tension: 0.1
          }
        ]
      },
      options: {
        ...chartOptions,
        plugins: {
          legend: {
            display: true,
            position: 'top'
          }
        }
      }
    })

    // Disk Chart
    this.charts.disk = new Chart(this.diskChartTarget, {
      type: 'line',
      data: {
        datasets: [{
          label: 'Disk Usage (%)',
          data: [],
          borderColor: 'rgb(255, 159, 64)',
          backgroundColor: 'rgba(255, 159, 64, 0.1)',
          tension: 0.1
        }]
      },
      options: {
        ...chartOptions,
        scales: {
          ...chartOptions.scales,
          y: { ...chartOptions.scales.y, max: 100 }
        }
      }
    })

    console.log("✅ All charts initialized:", Object.keys(this.charts))
  }

  async loadInitialData() {
    try {
      const response = await fetch(`/nodes/${this.nodeIdValue}/dashboard/metrics_data?range=${this.timeRange}`)
      const data = await response.json()
      
      if (data.data) {
        this.updateChartsWithHistoricalData(data.data)
      }
    } catch (error) {
      console.error("Error loading initial data:", error)
    }
  }

  updateChartsWithHistoricalData(data) {
    console.log("📈 Loading historical data into charts")

    // Clear existing data first to prevent conflicts with real-time updates
    this.clearAllChartData()

    // Update CPU chart
    if (this.charts.cpu && data.cpu) {
      console.log(`📊 Loading ${data.cpu.length} CPU data points`)
      this.charts.cpu.data.datasets[0].data = [...data.cpu] // Create a copy
      this.charts.cpu.update('none')
    }

    // Update Memory chart
    if (this.charts.memory && data.memory) {
      console.log(`📊 Loading ${data.memory.length} Memory data points`)
      this.charts.memory.data.datasets[0].data = [...data.memory] // Create a copy
      this.charts.memory.update('none')
    }

    // Update Load Average chart
    if (this.charts.load && data.load_average) {
      console.log(`📊 Loading Load Average data points`)
      this.charts.load.data.datasets[0].data = [...(data.load_average.load_1min || [])]
      this.charts.load.data.datasets[1].data = [...(data.load_average.load_5min || [])]
      this.charts.load.data.datasets[2].data = [...(data.load_average.load_15min || [])]
      this.charts.load.update('none')
    }

    // Update Disk chart (using root filesystem)
    if (this.charts.disk && data.disk_usage && data.disk_usage['/']) {
      console.log(`📊 Loading ${data.disk_usage['/'].length} Disk data points`)
      this.charts.disk.data.datasets[0].data = [...data.disk_usage['/']] // Create a copy
      this.charts.disk.update('none')
    }

    console.log("✅ Historical data loaded into all charts")
  }

  updateMetricsDisplay(metrics) {
    // Update CPU
    if (this.hasCpuUsageTarget) {
      this.cpuUsageTarget.textContent = `${metrics.cpu.usage_percent}%`
    }
    if (this.hasCpuProgressBarTarget) {
      this.cpuProgressBarTarget.style.width = `${metrics.cpu.usage_percent}%`
      this.cpuProgressBarTarget.className = `progress-bar ${this.getProgressBarClass(metrics.cpu.usage_percent, 70, 85)}`
    }

    // Update Memory
    if (this.hasMemoryUsageTarget) {
      this.memoryUsageTarget.textContent = `${metrics.memory.usage_percent}%`
    }
    if (this.hasMemoryProgressBarTarget) {
      this.memoryProgressBarTarget.style.width = `${metrics.memory.usage_percent}%`
      this.memoryProgressBarTarget.className = `progress-bar bg-success ${this.getProgressBarClass(metrics.memory.usage_percent, 75, 90)}`
    }

    // Update Disk (root filesystem)
    const rootDiskUsage = metrics.disk && metrics.disk['/'] ? metrics.disk['/'].usage_percent : 0
    if (this.hasDiskUsageTarget) {
      this.diskUsageTarget.textContent = `${rootDiskUsage}%`
    }
    if (this.hasDiskProgressBarTarget) {
      this.diskProgressBarTarget.style.width = `${rootDiskUsage}%`
      this.diskProgressBarTarget.className = `progress-bar bg-warning ${this.getProgressBarClass(rootDiskUsage, 80, 90)}`
    }

    // Update Uptime
    if (this.hasUptimeTarget && metrics.uptime) {
      this.uptimeTarget.textContent = metrics.uptime.formatted
    }

    // Update Health Status
    if (this.hasHealthStatusTarget) {
      this.healthStatusTarget.textContent = metrics.health_status.charAt(0).toUpperCase() + metrics.health_status.slice(1)
      this.healthStatusTarget.className = `badge bg-${this.getHealthStatusClass(metrics.health_status)}`
    }

    // Update Last Update Time
    if (this.hasLastUpdateTarget) {
      this.lastUpdateTarget.textContent = new Date(metrics.collected_at).toLocaleString()
    }

    // Update alerts
    this.updateAlerts(metrics)
  }

  updateCharts(metrics) {
    console.log("📊 Updating charts with metrics:", metrics)
    const timestamp = new Date(metrics.collected_at).getTime()
    console.log("⏰ Timestamp:", timestamp, "Date:", new Date(metrics.collected_at))

    // Update CPU chart
    if (this.charts.cpu) {
      console.log("📈 Updating CPU chart:", metrics.cpu.usage_percent)
      this.addDataPoint(this.charts.cpu, 0, { x: timestamp, y: metrics.cpu.usage_percent })
    } else {
      console.log("❌ CPU chart not available")
    }

    // Update Memory chart
    if (this.charts.memory) {
      console.log("📈 Updating Memory chart:", metrics.memory.usage_percent)
      this.addDataPoint(this.charts.memory, 0, { x: timestamp, y: metrics.memory.usage_percent })
    } else {
      console.log("❌ Memory chart not available")
    }

    // Update Load Average chart
    if (this.charts.load && metrics.load_average) {
      console.log("📈 Updating Load chart:", metrics.load_average)
      this.addDataPoint(this.charts.load, 0, { x: timestamp, y: metrics.load_average['1min'] })
      this.addDataPoint(this.charts.load, 1, { x: timestamp, y: metrics.load_average['5min'] })
      this.addDataPoint(this.charts.load, 2, { x: timestamp, y: metrics.load_average['15min'] })
    } else {
      console.log("❌ Load chart not available or no load_average data")
    }

    // Update Disk chart (root filesystem)
    if (this.charts.disk && metrics.disk && metrics.disk['/']) {
      console.log("📈 Updating Disk chart:", metrics.disk['/'].usage_percent)
      this.addDataPoint(this.charts.disk, 0, { x: timestamp, y: metrics.disk['/'].usage_percent })
    } else {
      console.log("❌ Disk chart not available or no disk data for /")
    }
  }

  addDataPoint(chart, datasetIndex, point) {
    console.log(`📍 Adding data point to dataset ${datasetIndex}:`, point)
    const dataset = chart.data.datasets[datasetIndex]

    // Check if this timestamp already exists to prevent duplicates (within 1 second tolerance)
    const existingPointIndex = dataset.data.findIndex(p => Math.abs(p.x - point.x) < 1000)
    if (existingPointIndex !== -1) {
      console.log(`⚠️ Similar timestamp found, updating existing point instead of adding`)
      dataset.data[existingPointIndex].y = point.y
      dataset.data[existingPointIndex].x = point.x // Update to exact timestamp
    } else {
      // Add new point and sort by timestamp
      dataset.data.push(point)
      dataset.data.sort((a, b) => a.x - b.x)

      // Keep only last 100 points for performance
      if (dataset.data.length > 100) {
        dataset.data.shift()
      }
    }

    console.log(`📊 Dataset now has ${dataset.data.length} points, updating chart...`)
    chart.update('none')
    console.log("✅ Chart updated")
  }

  clearAllChartData() {
    console.log("🧹 Clearing all chart data")

    // Clear data from all charts
    Object.values(this.charts).forEach(chart => {
      chart.data.datasets.forEach(dataset => {
        dataset.data = []
      })
    })
  }

  updateAlerts(metrics) {
    const alerts = []
    
    // Check CPU alerts
    if (metrics.cpu.usage_percent > 85) {
      alerts.push({ type: 'critical', message: `High CPU usage: ${metrics.cpu.usage_percent}%` })
    } else if (metrics.cpu.usage_percent > 70) {
      alerts.push({ type: 'warning', message: `Elevated CPU usage: ${metrics.cpu.usage_percent}%` })
    }
    
    // Check Memory alerts
    if (metrics.memory.usage_percent > 90) {
      alerts.push({ type: 'critical', message: `High memory usage: ${metrics.memory.usage_percent}%` })
    } else if (metrics.memory.usage_percent > 75) {
      alerts.push({ type: 'warning', message: `Elevated memory usage: ${metrics.memory.usage_percent}%` })
    }
    
    // Update alerts display
    if (alerts.length > 0 && this.hasAlertsContainerTarget) {
      this.alertsContainerTarget.style.display = 'block'
      this.alertsListTarget.innerHTML = alerts.map(alert => 
        `<div class="alert-item ${alert.type}">• ${alert.message}</div>`
      ).join('')
    } else if (this.hasAlertsContainerTarget) {
      this.alertsContainerTarget.style.display = 'none'
    }
  }

  getProgressBarClass(value, warningThreshold, criticalThreshold) {
    if (value >= criticalThreshold) return 'bg-danger'
    if (value >= warningThreshold) return 'bg-warning'
    return ''
  }

  getHealthStatusClass(status) {
    switch (status) {
      case 'healthy': return 'success'
      case 'warning': return 'warning'
      case 'critical': return 'danger'
      default: return 'secondary'
    }
  }

  updateConnectionStatus(status, type) {
    if (this.hasConnectionStatusTarget) {
      this.connectionStatusTarget.textContent = status
      this.connectionStatusTarget.className = `badge bg-${type}`
    }
  }

  // Action methods
  refreshData() {
    console.log("Refreshing dashboard data...")
    this.loadInitialData()
  }

  changeTimeRange(event) {
    event.preventDefault()
    const range = event.target.dataset.range
    if (range) {
      this.timeRange = range
      console.log(`Changing time range to: ${range}`)
      this.loadInitialData()
    }
  }
}
