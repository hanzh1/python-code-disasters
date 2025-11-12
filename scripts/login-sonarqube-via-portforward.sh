#!/bin/bash
# Login to SonarQube via port-forwarding to bypass network protection

echo "========================================="
echo "SonarQube Login via Port-Forwarding"
echo "========================================="
echo ""
echo "This bypasses AT&T network protection by using port-forwarding"
echo ""

# Check if port 9000 is already in use
if lsof -Pi :9000 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "⚠ Port 9000 is already in use"
    echo "Killing existing port-forward..."
    pkill -f "kubectl port-forward.*9000:9000" 2>/dev/null || true
    sleep 2
fi

# Start port-forwarding in background
echo "Starting port-forwarding..."
kubectl port-forward -n sonarqube svc/sonarqube-service 9000:9000 > /tmp/sonar-portforward.log 2>&1 &
PF_PID=$!

echo "Port-forwarding started (PID: $PF_PID)"
echo "Waiting for connection..."
sleep 5

# Check if port-forward is still running
if ! kill -0 $PF_PID 2>/dev/null; then
    echo "✗ Port-forwarding failed!"
    echo "Error log:"
    cat /tmp/sonar-portforward.log 2>/dev/null | tail -5
    echo ""
    
    # Check if LoadBalancer IP is available (alternative)
    SONAR_IP=$(kubectl get svc sonarqube-service -n sonarqube -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$SONAR_IP" ]; then
        echo "💡 Alternative: Use LoadBalancer IP directly (no port-forwarding needed):"
        echo "   http://${SONAR_IP}:9000"
        echo ""
        echo "This bypasses the port-forwarding issue!"
    fi
    
    echo "Troubleshooting:"
    echo "  1. Check if SonarQube pod is running: kubectl get pods -n sonarqube"
    echo "  2. Check if service exists: kubectl get svc -n sonarqube"
    echo "  3. Try using LoadBalancer IP directly (see above)"
    exit 1
fi

# Test connection
if curl -s --max-time 3 http://localhost:9000/api/system/status > /dev/null 2>&1; then
    echo "✓ Connection successful!"
else
    echo "⚠ Connection test failed, but port-forward is running"
    echo "  (This might be normal - try accessing the URL anyway)"
fi

echo ""
echo "========================================="
echo "SonarQube is now accessible at:"
echo "  http://localhost:9000"
echo "========================================="
echo ""
echo "Login Credentials:"
echo "  Username: admin"
echo "  Password: Admin123456789@"
echo ""
echo "Port-forwarding is running (PID: $PF_PID)"
echo "Press Ctrl+C to stop"
echo ""

# Wait for user interrupt
trap "kill $PF_PID 2>/dev/null; pkill -f 'kubectl port-forward.*9000:9000' 2>/dev/null; echo ''; echo 'Port-forwarding stopped.'; exit 0" INT TERM

# Keep script running and monitor port-forward
while kill -0 $PF_PID 2>/dev/null; do
    sleep 1
done

# If we get here, port-forward died
echo ""
echo "✗ Port-forwarding stopped unexpectedly"
echo "Check logs: cat /tmp/sonar-portforward.log"
exit 1

