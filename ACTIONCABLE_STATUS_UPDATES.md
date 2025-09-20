# Live Node Status Updates with ActionCable

This document explains the live node status update system implemented using ActionCable.

## Overview

The system provides real-time updates of node provisioning status using ActionCable WebSocket connections. When nodes are being provisioned, configured, or destroyed, users see live status updates without needing to refresh the page.

## Components

### 1. Node Model (`app/models/node.rb`)
- Added `status` column with predefined statuses: pending, provisioning, configuring, active, error, destroying, destroyed
- Status management methods: `update_status!`, `status_display`, `status_badge_class`
- ActionCable broadcasting after status changes

### 2. ActionCable Channel (`app/channels/node_status_channel.rb`)
- Handles WebSocket subscriptions for node status updates
- Supports subscription to:
  - All node status updates
  - Specific node updates
  - Cluster-specific updates

### 3. Background Services
- **CreateService**: Updates status during provisioning (provisioning → configuring → active/error)
- **DestroyService**: Updates status during destruction (destroying → destroyed/error)

### 4. Frontend (Stimulus Controller)
- **File**: `app/javascript/controllers/node_status_controller.js`
- Handles WebSocket connections and DOM updates
- Shows toast notifications for status changes
- Includes fallback polling for reliability

### 5. Views
- Updated to show dynamic status badges and messages
- Uses helper methods for consistent status display
- Includes data attributes for ActionCable targeting

## Usage

### In Views
Add the `data-controller="node-status"` attribute to containers that should receive updates:

```erb
<!-- For cluster pages (all nodes) -->
<div data-controller="node-status" data-node-status-cluster-id-value="<%= @cluster.id %>">
  <!-- node list -->
</div>

<!-- For individual node pages -->
<div data-controller="node-status" 
     data-node-status-node-id-value="<%= @node.id %>" 
     data-node-status-cluster-id-value="<%= @cluster.id %>">
  <!-- node details -->
</div>
```

### Status Display
Use helper methods for consistent status display:

```erb
<%= node_status_badge(node) %>
<%= node_status_message_area(node) %>
```

### In Services
Update node status with messages:

```ruby
node.update_status!('provisioning', 'Starting infrastructure provisioning...')
node.update_status!('configuring', 'Installing PostgreSQL...')
node.update_status!('active', 'Node is ready')
node.update_status!('error', 'Failed: error message')
```

## Configuration

### Cable Configuration (`config/cable.yml`)
- Development: async adapter
- Production: solid_cable (persistent storage)

### Routes (`config/routes.rb`)
- ActionCable mounted at `/cable`
- Status API endpoints for fallback

### Importmap (`config/importmap.rb`)
- ActionCable JavaScript library pinned

## Testing

Use the test script to simulate status changes:

```bash
bin/rails runner script/test_node_status_broadcast.rb
```

## Troubleshooting

1. **Check browser console** for ActionCable connection logs
2. **Verify WebSocket connection** in browser developer tools
3. **Check Rails logs** for ActionCable broadcast messages
4. **Fallback API** available at `/clusters/:cluster_id/nodes/status` and `/nodes/:id/status`

## Status Flow Examples

### Node Provisioning
1. pending → provisioning → configuring → active
2. User sees: "Starting infrastructure..." → "Installing PostgreSQL..." → "Node is ready"

### Node Destruction  
1. active → destroying → destroyed
2. User sees: "Starting destruction..." → "Node destroyed"

### Error Handling
1. Any status → error
2. User sees: "Failed: [error message]"

## Security Notes

- No authentication required for status updates (read-only)
- Consider adding authentication in production environments
- Status messages should not contain sensitive information
