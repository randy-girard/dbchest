#!/bin/bash

# DBChest Node Metrics Collector
# This script collects system metrics and reports them to the DBChest API
# It should be run periodically via cron

set -e

# Configuration - these will be replaced during deployment
DBCHEST_API_URL="{{DBCHEST_API_URL}}"
NODE_ID="{{NODE_ID}}"
METRICS_API_KEY="{{METRICS_API_KEY}}"
LOG_FILE="/var/log/dbchest-metrics.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to get CPU usage percentage
get_cpu_usage() {
    # Get CPU usage from /proc/stat
    # We take two samples 1 second apart for accuracy
    cpu1=$(grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8}')
    idle1=$(grep '^cpu ' /proc/stat | awk '{print $5}')
    
    sleep 1
    
    cpu2=$(grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8}')
    idle2=$(grep '^cpu ' /proc/stat | awk '{print $5}')
    
    cpu_delta=$((cpu2 - cpu1))
    idle_delta=$((idle2 - idle1))
    
    if [ $cpu_delta -eq 0 ]; then
        echo "0.00"
    else
        cpu_usage=$(echo "scale=2; 100 * (1 - $idle_delta / $cpu_delta)" | bc -l)
        echo "$cpu_usage"
    fi
}

# Function to get memory information
get_memory_info() {
    # Parse /proc/meminfo
    local mem_total=$(grep '^MemTotal:' /proc/meminfo | awk '{print int($2/1024)}')
    local mem_available=$(grep '^MemAvailable:' /proc/meminfo | awk '{print int($2/1024)}')
    local mem_free=$(grep '^MemFree:' /proc/meminfo | awk '{print int($2/1024)}')
    local buffers=$(grep '^Buffers:' /proc/meminfo | awk '{print int($2/1024)}')
    local cached=$(grep '^Cached:' /proc/meminfo | awk '{print int($2/1024)}')
    local swap_total=$(grep '^SwapTotal:' /proc/meminfo | awk '{print int($2/1024)}')
    local swap_free=$(grep '^SwapFree:' /proc/meminfo | awk '{print int($2/1024)}')
    
    # Calculate used memory (total - available)
    local mem_used=$((mem_total - mem_available))
    local swap_used=$((swap_total - swap_free))
    
    echo "{\"total_mb\":$mem_total,\"used_mb\":$mem_used,\"available_mb\":$mem_available,\"swap_total_mb\":$swap_total,\"swap_used_mb\":$swap_used}"
}

# Function to get disk usage information
get_disk_usage() {
    local disk_json="{"
    local first=true

    # Use process substitution to avoid subshell issues
    while IFS= read -r line; do
        # Parse df output
        filesystem=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        use_percent=$(echo "$line" | awk '{print $5}')
        mount=$(echo "$line" | awk '{print $6}')

        # Remove % from use_percent
        use_percent_num=$(echo "$use_percent" | sed 's/%//')

        # Skip if no valid percentage
        if [[ ! "$use_percent_num" =~ ^[0-9]+$ ]]; then
            continue
        fi

        # Convert sizes to GB (remove units and convert)
        size_gb=$(echo "$size" | sed 's/[^0-9.]//g')
        used_gb=$(echo "$used" | sed 's/[^0-9.]//g')
        avail_gb=$(echo "$avail" | sed 's/[^0-9.]//g')

        # Handle different unit suffixes
        case "$size" in
            *T) size_gb=$(echo "scale=2; $size_gb * 1024" | bc -l 2>/dev/null || echo "$size_gb") ;;
            *M) size_gb=$(echo "scale=2; $size_gb / 1024" | bc -l 2>/dev/null || echo "0.1") ;;
            *K) size_gb=$(echo "scale=2; $size_gb / 1024 / 1024" | bc -l 2>/dev/null || echo "0.001") ;;
        esac

        case "$used" in
            *T) used_gb=$(echo "scale=2; $used_gb * 1024" | bc -l 2>/dev/null || echo "$used_gb") ;;
            *M) used_gb=$(echo "scale=2; $used_gb / 1024" | bc -l 2>/dev/null || echo "0.1") ;;
            *K) used_gb=$(echo "scale=2; $used_gb / 1024 / 1024" | bc -l 2>/dev/null || echo "0.001") ;;
        esac

        case "$avail" in
            *T) avail_gb=$(echo "scale=2; $avail_gb * 1024" | bc -l 2>/dev/null || echo "$avail_gb") ;;
            *M) avail_gb=$(echo "scale=2; $avail_gb / 1024" | bc -l 2>/dev/null || echo "0.1") ;;
            *K) avail_gb=$(echo "scale=2; $avail_gb / 1024 / 1024" | bc -l 2>/dev/null || echo "0.001") ;;
        esac

        if [ "$first" = true ]; then
            first=false
        else
            disk_json="$disk_json,"
        fi

        disk_json="$disk_json\"$mount\":{\"usage_percent\":$use_percent_num,\"total_gb\":$size_gb,\"used_gb\":$used_gb,\"available_gb\":$avail_gb,\"filesystem\":\"$filesystem\"}"
    done < <(df -h 2>/dev/null | grep -E '^/dev/' | head -10)

    # If no devices found, try to get root filesystem
    if [ "$first" = true ]; then
        local root_line=$(df -h / 2>/dev/null | tail -n 1)
        if [ -n "$root_line" ]; then
            filesystem=$(echo "$root_line" | awk '{print $1}')
            size=$(echo "$root_line" | awk '{print $2}')
            used=$(echo "$root_line" | awk '{print $3}')
            avail=$(echo "$root_line" | awk '{print $4}')
            use_percent=$(echo "$root_line" | awk '{print $5}')
            use_percent_num=$(echo "$use_percent" | sed 's/%//')

            if [[ "$use_percent_num" =~ ^[0-9]+$ ]]; then
                disk_json="$disk_json\"\/\":{\"usage_percent\":$use_percent_num,\"total\":\"$size\",\"used\":\"$used\",\"available\":\"$avail\",\"filesystem\":\"$filesystem\"}"
            fi
        fi
    fi

    echo "$disk_json}"
}

# Function to get network statistics
get_network_stats() {
    local net_json="{"
    local first=true

    # Use process substitution to avoid subshell issues
    while IFS= read -r line; do
        interface=$(echo "$line" | awk -F: '{print $1}' | tr -d ' ')

        # Skip loopback interface and empty lines
        if [ "$interface" = "lo" ] || [ -z "$interface" ]; then
            continue
        fi

        stats=$(echo "$line" | awk -F: '{print $2}')
        rx_bytes=$(echo "$stats" | awk '{print $1}' | tr -d ' ')
        rx_packets=$(echo "$stats" | awk '{print $2}' | tr -d ' ')
        tx_bytes=$(echo "$stats" | awk '{print $9}' | tr -d ' ')
        tx_packets=$(echo "$stats" | awk '{print $10}' | tr -d ' ')

        # Validate that we have numeric values
        if [[ "$rx_bytes" =~ ^[0-9]+$ ]] && [[ "$tx_bytes" =~ ^[0-9]+$ ]]; then
            if [ "$first" = true ]; then
                first=false
            else
                net_json="$net_json,"
            fi

            net_json="$net_json\"$interface\":{\"rx_bytes\":$rx_bytes,\"rx_packets\":$rx_packets,\"tx_bytes\":$tx_bytes,\"tx_packets\":$tx_packets}"
        fi
    done < <(tail -n +3 /proc/net/dev 2>/dev/null | head -10)

    echo "$net_json}"
}

# Function to get load average
get_load_average() {
    local load_avg=$(cat /proc/loadavg)
    local load_1min=$(echo "$load_avg" | awk '{print $1}')
    local load_5min=$(echo "$load_avg" | awk '{print $2}')
    local load_15min=$(echo "$load_avg" | awk '{print $3}')
    
    echo "{\"1min\":$load_1min,\"5min\":$load_5min,\"15min\":$load_15min}"
}

# Function to get system uptime
get_uptime() {
    local uptime_seconds=$(cat /proc/uptime | awk '{print int($1)}')
    echo "$uptime_seconds"
}

# Function to collect all metrics
collect_metrics() {
    # Collect all metrics (logging moved to main function to avoid stdout pollution)
    local cpu_usage=$(get_cpu_usage)
    local memory_info=$(get_memory_info)
    local disk_usage=$(get_disk_usage)
    local network_stats=$(get_network_stats)
    local load_average=$(get_load_average)
    local uptime_seconds=$(get_uptime)
    local collected_at=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # Extract memory values from JSON
    local memory_total=$(echo "$memory_info" | jq -r '.total_mb')
    local memory_used=$(echo "$memory_info" | jq -r '.used_mb')
    local memory_available=$(echo "$memory_info" | jq -r '.available_mb')
    local swap_total=$(echo "$memory_info" | jq -r '.swap_total_mb')
    local swap_used=$(echo "$memory_info" | jq -r '.swap_used_mb')
    
    # Build JSON payload
    local payload=$(cat <<EOF
{
    "node_metric": {
        "collected_at": "$collected_at",
        "cpu_usage_percent": $cpu_usage,
        "memory_total_mb": $memory_total,
        "memory_used_mb": $memory_used,
        "memory_available_mb": $memory_available,
        "swap_total_mb": $swap_total,
        "swap_used_mb": $swap_used,
        "disk_usage": $disk_usage,
        "network_stats": $network_stats,
        "load_average": $load_average,
        "uptime_seconds": $uptime_seconds
    }
}
EOF
)
    
    echo "$payload"
}

# Function to send metrics to API
send_metrics() {
    local payload="$1"
    local api_endpoint="${DBCHEST_API_URL}/nodes/${NODE_ID}/metrics"
    
    log "Sending metrics to: $api_endpoint"
    
    # Send POST request with metrics
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $METRICS_API_KEY" \
        -d "$payload" \
        "$api_endpoint" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        log "Metrics sent successfully (HTTP $http_code)"
        return 0
    else
        log "Failed to send metrics (HTTP $http_code): $response_body"
        return 1
    fi
}

# Main execution
main() {
    # Check if required tools are available (should be installed by cloud init)
    if ! command -v bc >/dev/null 2>&1; then
        log "Error: bc calculator not found. This should have been installed during setup."
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        log "Error: jq not found. This should have been installed during setup."
        exit 1
    fi

    # Collect and send metrics
    log "Starting metrics collection..."
    local metrics_payload=$(collect_metrics)

    if [ $? -eq 0 ]; then
        send_metrics "$metrics_payload"
        if [ $? -eq 0 ]; then
            log "Metrics collection and reporting completed successfully"
        else
            log "Failed to send metrics to API"
            exit 1
        fi
    else
        log "Failed to collect metrics"
        exit 1
    fi
}

# Run main function
main "$@"
