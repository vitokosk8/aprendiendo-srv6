#!/usr/bin/env bash
# Comprueba que el laboratorio del módulo 04 funciona. Uso: ./verificar.sh
L=clab-m04
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a FRR (máx. 30 s)..."
for i in $(seq 1 15); do
  docker exec $L-r1 vtysh -c "show ipv6 route 3fff:0:2::/64" 2>/dev/null | grep -q 'via' && break
  sleep 2
done

check "r1: ruta conectada a 3fff:0:1::/64"          "docker exec $L-r1 vtysh -c 'show ipv6 route 3fff:0:1::/64' | grep -qE 'C>?\\*'"
check "r1: ruta estática a 3fff:0:2::/64 vía r2"     "docker exec $L-r1 vtysh -c 'show ipv6 route 3fff:0:2::/64' | grep -q 'S>'"
check "r1: ruta estática a 3fff:0:3::/64 vía r3"     "docker exec $L-r1 vtysh -c 'show ipv6 route 3fff:0:3::/64' | grep -q '3fff:0:13::3'"
check "h1 → h2 (red tras r2)"                        "docker exec $L-h1 ping -c2 -W2 3fff:0:2::20"
check "h1 → h3 (red tras r3)"                        "docker exec $L-h1 ping -c2 -W2 3fff:0:3::30"
check "h2 → h3 (r2 llega a r3 directo)"              "docker exec $L-h2 ping -c2 -W2 3fff:0:3::30"
check "h3 → h1 (vuelta completa)"                    "docker exec $L-h3 ping -c2 -W2 3fff:0:1::10"
check "h1: destino sin ruta falla"                   "! docker exec $L-h1 ping -c1 -W2 3fff:0:99::1"
check "camino h1→h3 pasa por r3 (traceroute)"        "docker exec $L-h1 traceroute -6 -n -m3 3fff:0:3::30 | grep -q '3fff:0:13::3'"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  docker exec $L-r1 vtysh -c "show ipv6 route static"
  docker exec $L-h1 ip -6 route
fi
