#!/bin/bash
# brother_finder.sh

# Постоянный идентификатор принтера
PRINTER_UUID="e3248000-80ce-11db-8000-4cebbd84df72"
PRINTER_NAME="BRW4CEBBD84DF72.local"

echo "🔍 Looking for Brother QL-810W printer..."

# Try mDNS first
if ping -c 1 -W 2 $PRINTER_NAME &>/dev/null; then
    IP=$(ping -c 1 $PRINTER_NAME | grep -oP '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    echo "✅ Printer found!"
    echo "   Name: Brother QL-810W"
    echo "   IP: $IP"
    echo "   Hostname: $PRINTER_NAME"
    echo "   MAC: 4c:eb:bd:84:df:72"
    echo ""
    echo "🌐 Web interface: http://$IP"
    echo "🖨️  Print via: ipp://$PRINTER_NAME/ipp/print"
    echo "📁 Admin: http://$IP/net/net/airprint.html"
else
    echo "❌ Printer not found on network"
    echo "💡 Check if printer is powered on and connected to the same network"
fi

