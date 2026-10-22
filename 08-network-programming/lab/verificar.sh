#!/usr/bin/env bash
# Comprueba que el laboratorio del módulo 08 funciona. Uso: ./verificar.sh
L=clab-m08
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS y a los SID (máx. 60 s)..."
for i in $(seq 1 30); do
  docker exec $L-r1 vtysh -c "show ipv6 route isis" 2>/dev/null | grep -q '5f00:0:3::/48' &&
  docker exec $L-r3 ip -6 route show 5f00:0:3:dc04::/128 2>/dev/null | grep -q seg6local && break
  sleep 2
done

check "r2 tiene el SID End"                        "docker exec $L-r2 ip -6 route show 5f00:0:2:e000::/128 | grep -q 'action End'"
check "r3 tiene el SID End.DX4 (entrega IPv4)"      "docker exec $L-r3 ip -6 route show 5f00:0:3:dc04::/128 | grep -q 'End.DX4'"
check "r3 tiene el SID End.DT6"                     "docker exec $L-r3 ip -6 route show 5f00:0:3:d600::/128 | grep -q 'End.DT6'"
check "r1 tiene la ruta de encap hacia 10.0.2.0/24" "docker exec $L-r1 ip route show 10.0.2.0/24 | grep -q 'encap seg6'"
check "h1 → h2 IPv6 (plano, por el IGP)"            "docker exec $L-h1 ping -c2 -W2 3fff:0:2::20"
check "h1 → h2 IPv4 sobre SRv6 (10.0.2.20)"         "docker exec $L-h1 ping -c2 -W2 10.0.2.20"
check "h2 → h1 IPv4 sobre SRv6 (vuelta)"            "docker exec $L-h2 ping -c2 -W2 10.0.1.10"

# El ping IPv4 debe viajar dentro de una SRH por el núcleo
echo "Comprobando que el IPv4 viaja encapsulado en SRv6 por r2..."
cap() {
  docker run --rm --net container:$L-r2 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni eth1 -c1 'ip6[6]==43' >/tmp/m08cap.txt 2>&1 &
  sleep 1
  docker exec $L-h1 ping -c3 -W1 10.0.2.20 >/dev/null 2>&1
  wait
  grep -q 'srcrt' /tmp/m08cap.txt || grep -qi 'rt6\|segment' /tmp/m08cap.txt
}
check "el IPv4 de h1→h2 cruza r2 dentro de una SRH" "cap"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  docker exec $L-r1 ip route show 10.0.2.0/24
  docker exec $L-r3 ip -6 route show | grep seg6local
  docker exec $L-h1 ping -c2 -W2 10.0.2.20 2>&1 | tail -3
  cat /tmp/m08cap.txt 2>/dev/null | head -3
fi
