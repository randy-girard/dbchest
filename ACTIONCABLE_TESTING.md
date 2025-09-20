# Manual ActionCable Test Instructions

## Browser Console Tests

After loading a page with nodes, open the browser console (F12) and run these commands:

### 1. Test ActionCable Availability
```javascript
// Check if ActionCable is loaded
console.log("ActionCable:", typeof ActionCable);
console.log("createConsumer:", typeof createConsumer);

// Test creating a consumer
if (typeof ActionCable !== 'undefined') {
  const testConsumer = ActionCable.createConsumer();
  console.log("Test consumer:", testConsumer);
}
```

### 2. Test Node Status Controller
```javascript
// Get the controller
const controller = window.nodeController;
console.log("Controller:", controller);

// Test connection
if (controller) {
  controller.testConnection();
}
```

### 3. Test Direct Broadcast Reception
```javascript
// Create a test subscription to see if messages are received
if (typeof ActionCable !== 'undefined') {
  const testConsumer = ActionCable.createConsumer();
  const testSubscription = testConsumer.subscriptions.create("NodeStatusChannel", {
    connected: () => console.log("✅ Test subscription connected"),
    disconnected: () => console.log("❌ Test subscription disconnected"),
    received: (data) => console.log("📥 Test subscription received:", data),
    rejected: () => console.error("❌ Test subscription rejected")
  });
  
  console.log("Test subscription created:", testSubscription);
}
```

### 4. Test Manual Status Update
```javascript
// If you have a node ID (e.g., 20), test updating its status
const nodeId = 20; // Replace with actual node ID
fetch(`/nodes/${nodeId}/status`, {
  method: 'GET',
  headers: { 'Accept': 'application/json' }
})
.then(response => response.json())
.then(data => {
  console.log("Current status:", data);
  
  // Try to simulate an update
  if (window.nodeController) {
    window.nodeController.updateNodeStatus(data);
  }
});
```

## Rails Console Test

In a separate terminal, run:
```bash
bin/rails console
```

Then execute:
```ruby
# Test direct broadcast
node = Node.first
if node
  node.update_status!('active', 'Manual test from console')
else
  puts "No nodes found"
end
```

## Expected Results

1. **ActionCable Available**: Should see ActionCable and createConsumer as functions
2. **Consumer Creation**: Should successfully create a consumer
3. **Connection**: Should see "Connected to NodeStatusChannel" in console
4. **Message Reception**: When running Rails console test, should see "Received node status update" in browser
5. **DOM Update**: Status badges should change in real-time

## Troubleshooting

If ActionCable is still not available:
1. Check importmap: `bin/importmap json`
2. Check for JavaScript errors in console
3. Verify Rails server is running on same port as browser
4. Check if WebSocket connection is blocked by firewall/proxy
