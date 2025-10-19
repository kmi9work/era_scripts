#!/bin/bash
# Script to detect system IP address for development

# If DEV_IP is already set as environment variable, use it
if [ -n "$DEV_IP" ]; then
    echo "Using manually set IP: $DEV_IP"
    DETECTED_IP="$DEV_IP"
else
    # Try to detect IP address automatically
    # Method 1: Get IP from default route interface
    DETECTED_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    
    # Method 2: If method 1 fails, try getting from ip addr
    if [ -z "$DETECTED_IP" ]; then
        DETECTED_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    # Method 3: If still no IP, try hostname -I
    if [ -z "$DETECTED_IP" ]; then
        DETECTED_IP=$(hostname -I | awk '{print $1}')
    fi
    
    if [ -z "$DETECTED_IP" ]; then
        echo "ERROR: Could not detect IP address automatically"
        echo "Please set DEV_IP environment variable manually:"
        echo "  export DEV_IP=your.ip.address"
        exit 1
    fi
    
    echo "Auto-detected IP: $DETECTED_IP"
fi

# Export the IP for use in other scripts
export DEV_IP="$DETECTED_IP"

# Load ports from .env if it exists, otherwise use defaults
BACKEND_PORT=${BACKEND_PORT:-3000}
FRONTEND_PORT=${FRONTEND_PORT:-5173}

# Generate .env file
cat > "$(dirname "$0")/../.env" <<EOF
# Development environment configuration
# Auto-generated on $(date)

# System IP address
DEV_IP=$DETECTED_IP

# Application ports
BACKEND_PORT=$BACKEND_PORT
FRONTEND_PORT=$FRONTEND_PORT

# Generated URLs
BACKEND_URL=http://$DETECTED_IP:$BACKEND_PORT
FRONTEND_URL=http://$DETECTED_IP:$FRONTEND_PORT
EOF

echo ".env file created successfully"
echo "Backend will be available at: http://$DETECTED_IP:$BACKEND_PORT"
echo "Frontend will be available at: http://$DETECTED_IP:$FRONTEND_PORT"

# Return the IP address
echo "$DETECTED_IP"

