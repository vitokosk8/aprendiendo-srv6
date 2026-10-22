#!/usr/bin/env bash
# Comprueba que el laboratorio del módulo 02 funciona. Uso: ./verificar.sh
L=clab-m02
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a FRR (máx. 30 s)..."
for i in $(seq 1 15); do
  docker exec $L-r1 ip -6 route show 3fff:0:2::/64 2>/dev/null | grep -q via && break
  sleep 2
done

check "r1 tiene ruta hacia 3fff:0:2::/64"            "docker exec $L-r1 ip -6 route show 3fff:0:2::/64 | grep -q via"
check "r2 tiene ruta hacia 3fff:0:1::/64"            "docker exec $L-r2 ip -6 route show 3fff:0:1::/64 | grep -q via"
check "MTU 1400 en r1 eth2"                          "docker exec $L-r1 ip link show eth2 | grep -q 'mtu 1400'"
check "MTU 1400 en r2 eth1"                          "docker exec $L-r2 ip link show eth1 | grep -q 'mtu 1400'"
check "h1 no tiene ruta por defecto por eth0"        "! docker exec $L-h1 ip -6 route show default | grep -q eth0"
check "h1 hace ping a h2 (3fff:0:2::10)"             "docker exec $L-h1 ping -c2 -W2 3fff:0:2::10"
check "Scapy disponible en h1"                       "docker exec $L-h1 python3 -c 'import scapy.all'"
check "Script /lab/paquetes.py montado en h1"        "docker exec $L-h1 test -f /lab/paquetes.py"
check "paquetes.py basico recibe respuesta de h2"    "docker exec $L-h1 python3 /lab/paquetes.py basico | grep -q 'RESPUESTA de 3fff:0:2::10'"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  docker exec $L-h1 ip -6 addr show dev eth1
  docker exec $L-h1 ip -6 route
  docker exec $L-r1 ip -6 route
  docker exec $L-h1 python3 /lab/paquetes.py basico 2>&1 | tail -5
fi
