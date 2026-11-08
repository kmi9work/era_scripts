#!/bin/bash
# brother_finder.sh — находит принтеры Brother QL в локальной сети по mDNS.
#
# Список принтеров: "подпись|mDNS-хост|MAC|UUID|серийный номер"
# Новый принтер добавляется одной строкой в массив ниже.
# UUID у Brother QL-810W = e3248000-80ce-11db-8000-<MAC без двоеточий>.

PRINTERS=(
    "Brother QL-810W (новый)|BRW4CEBBD84B979.local|4c:eb:bd:84:b9:79|e3248000-80ce-11db-8000-4cebbd84b979|G0Z677262"
    "Brother QL-810W (старый)|BRW4CEBBD84DF72.local|4c:eb:bd:84:df:72|e3248000-80ce-11db-8000-4cebbd84df72|"
)

echo "🔍 Looking for Brother QL printers..."

found=0

for entry in "${PRINTERS[@]}"; do
    IFS='|' read -r label host mac uuid serial <<< "$entry"

    IP=$(ping -c 1 -W 2 "$host" 2>/dev/null \
         | grep -oP '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

    if [ -z "$IP" ]; then
        echo "❌ $label — не найден ($host)"
        continue
    fi

    echo "✅ $label"
    echo "   Name:     $host"
    echo "   IP:       $IP"
    echo "   MAC:      $mac"
    [ -n "$serial" ] && echo "   Serial:   $serial"
    echo "   UUID:     $uuid"
    echo "   Web UI:   http://$IP/"
    echo "   Login:    http://$IP/general/status.html"
    echo "   Print:    ipp://$host/ipp/print"
    echo ""
    found=$((found + 1))
done

if [ "$found" -eq 0 ]; then
    echo "❌ Ни один принтер не найден в сети"
    echo "💡 Проверь, что принтер включён и подключён к той же сети (Wi-Fi)."
    echo "   Если принтер подключён по USB, веб-интерфейс доступен через"
    echo "   usb_tunnel_proxy.py: sudo python3 usb_tunnel_proxy.py --port 8080"
fi

exit 0
