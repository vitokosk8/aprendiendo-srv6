#!/usr/bin/env bash
# Comprueba que el laboratorio del módulo 03 funciona. Uso: ./verificar.sh
L=clab-m03
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando el Router Advertisement de r1 (máx. 40 s)..."
for i in $(seq 1 20); do
  docker exec $L-h1 ip -6 route show default 2>/dev/null | grep -q 'proto ra' && break
  sleep 2
done

check "sw1: bridge br0 con 4 puertos"              "[ \$(docker exec $L-sw1 sh -c 'ls /sys/class/net/br0/brif | wc -l') -eq 4 ]"
check "sw1: sin IPv6 (solo conmuta tramas)"        "! docker exec $L-sw1 ip -6 addr show dev br0 | grep -q inet6"
check "h1 tiene 3fff:0:10::10 (sin DAD fallido)"   "docker exec $L-h1 ip -6 addr show dev eth1 | grep 'inet6 3fff:0:10::10/64' | grep -vq -e tentative -e dadfailed"
check "h1 no tiene direcciones SLAAC"              "! docker exec $L-h1 ip -6 addr show dev eth1 | grep -q kernel_ra"
check "h1 aprende el router por defecto por RA"    "docker exec $L-h1 ip -6 route show default | grep -q 'proto ra'"
check "h1 no tiene ruta por defecto por eth0"      "! docker exec $L-h1 ip -6 route show default | grep -q eth0"
check "h1 hace ping a h2 (misma LAN)"              "docker exec $L-h1 ping -c2 -W2 3fff:0:10::20"
check "h1 hace ping a h3 (misma LAN)"              "docker exec $L-h1 ping -c2 -W2 3fff:0:10::30"
check "h1 hace ping a h4 (a través de r1)"         "docker exec $L-h1 ping -c2 -W2 3fff:0:40::40"
check "Scapy disponible en h3"                     "docker exec $L-h3 python3 -c 'import scapy.all'"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  docker exec $L-sw1 ip -d link show br0 | head -3
  docker exec $L-sw1 bridge link
  docker exec $L-h1 ip -6 addr show dev eth1
  docker exec $L-h1 ip -6 route
fi
