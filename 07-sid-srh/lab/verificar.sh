#!/usr/bin/env bash
# Comprueba que el laboratorio del módulo 07 funciona. Uso: ./verificar.sh
L=clab-m07
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a que IS-IS converja y los SID estén instalados (máx. 60 s)..."
for i in $(seq 1 30); do
  docker exec $L-r1 vtysh -c "show ipv6 route isis" 2>/dev/null | grep -q '5f00:0:3::/64' &&
  docker exec $L-r2 ip -6 route show 5f00:0:2:e000::/128 2>/dev/null | grep -q seg6local && break
  sleep 2
done

check "r1 alcanza el bloque de SID de r2 (5f00:0:2::/64)"  "docker exec $L-r1 vtysh -c 'show ipv6 route isis' | grep -q '5f00:0:2::/64'"
check "r1 alcanza el bloque de SID de r3 (5f00:0:3::/64)"  "docker exec $L-r1 vtysh -c 'show ipv6 route isis' | grep -q '5f00:0:3::/64'"
check "r2 tiene el SID End (5f00:0:2:e000::)"              "docker exec $L-r2 ip -6 route show 5f00:0:2:e000::/128 | grep -q 'action End'"
check "r3 tiene el SID End.DT6 (5f00:0:3:e000::)"          "docker exec $L-r3 ip -6 route show 5f00:0:3:e000::/128 | grep -q 'action End.DT6'"
check "h1 → h2 (IPv6 normal, sin SRv6)"                    "docker exec $L-h1 ping -c2 -W2 3fff:0:2::20"
check "Scapy disponible en h1"                             "docker exec $L-h1 python3 -c 'import scapy.all'"
check "srh.py construir genera una SRH"                    "docker exec $L-h1 python3 /lab/srh.py construir | grep -q 'Segments Left'"
check "srh.py enviar: el paquete SRv6 recorre r2 y r3"    "docker exec $L-h1 python3 /lab/srh.py enviar | grep -q 'RESPUESTA de 3fff:0:2::20'"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  docker exec $L-r2 ip -6 route show | grep seg6
  docker exec $L-r3 ip -6 route show | grep seg6
  docker exec $L-h1 python3 /lab/srh.py enviar 2>&1 | tail -5
fi
