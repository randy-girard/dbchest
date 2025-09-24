#!/bin/bash

# Test script to verify detached execution works
echo "=== DBChest Detached Execution Test ===" | tee -a /var/log/dbchest-setup.log

# Test the detached wrapper script creation
cat > /tmp/test_wrapper.sh << 'EOF'
#!/bin/bash
# Detach from SSH session completely
nohup setsid /bin/sleep 10 > /var/log/dbchest-test.log 2>&1 < /dev/null &
# Write the PID for monitoring
echo $! > /var/log/dbchest-test.pid
exit 0
EOF

chmod +x /tmp/test_wrapper.sh

echo "Testing detached execution..." | tee -a /var/log/dbchest-setup.log
/tmp/test_wrapper.sh

# Check if the process started
sleep 2
if [ -f /var/log/dbchest-test.pid ]; then
    PID=$(cat /var/log/dbchest-test.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "SUCCESS: Detached process $PID is running" | tee -a /var/log/dbchest-setup.log
    else
        echo "WARNING: Process $PID not found" | tee -a /var/log/dbchest-setup.log
    fi
else
    echo "ERROR: PID file not created" | tee -a /var/log/dbchest-setup.log
fi

echo "Test completed. Check /var/log/dbchest-setup.log for details" | tee -a /var/log/dbchest-setup.log
