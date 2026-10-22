#!/usr/bin/env bash
# Comprueba que el laboratorio del módulo 01 funciona. Uso: ./verificar.sh
L=clab-m01
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando direcciones SLAAC (máx. 60 s)..."
for i in $(seq 1 30); do
  docker exec $L-h1 ip -6 addr show dev eth1 scope global | grep -q 'inet6 2001:db8:1:' &&
  docker exec $L-h2 ip -6 addr show dev eth1 scope global | grep -q 'inet6 2001:db8:2:' && break
  sleep 2
done

H2=$(docker exec $L-h2 ip -6 -o addr show dev eth1 scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
R1LL=$(docker exec $L-r1 ip -6 -o addr show dev eth1 scope link | awk '{print $4}' | cut -d/ -f1)

check "h1 tiene dirección SLAAC en 2001:db8:1::/64" "docker exec $L-h1 ip -6 addr show dev eth1 | grep -q 'inet6 2001:db8:1:'"
check "h2 tiene dirección SLAAC en 2001:db8:2::/64" "[ -n '$H2' ]"
check "h1 tiene ruta por defecto aprendida por RA"   "docker exec $L-h1 ip -6 route show default | grep -q 'proto ra'"
check "h1 no tiene ruta por defecto por eth0"        "! docker exec $L-h1 ip -6 route show default | grep -q eth0"
check "h1 hace ping a r1 (global)"                   "docker exec $L-h1 ping -c1 -W2 2001:db8:1::1"
check "h1 hace ping a r1 (link-local con zone ID)"   "docker exec $L-h1 ping -c1 -W2 $R1LL%eth1"
check "h1 hace ping a h2 a través de r1"             "docker exec $L-h1 ping -c1 -W2 $H2"
check "tcpdump disponible en h1"                     "docker exec $L-h1 which tcpdump"

echo; echo "Resultado: $ok correctas, $fail fallidas"
echo; echo "Información para depurar:"
docker exec $L-h1 ip -6 addr show dev eth1
docker exec $L-h1 ip -6 route
docker exec $L-h1 ip link show dev eth1 | grep ether
