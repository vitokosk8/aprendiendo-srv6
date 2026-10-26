#!/usr/bin/env bash
# Comprueba que el laboratorio del módulo 09 funciona. Uso: ./verificar.sh
L=clab-m09
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap \'rm -rf "$T"\' EXIT
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS y a los SID (máx. 60 s)..."
for i in $(seq 1 30); do
  docker exec $L-r1 vtysh -c "show ipv6 route isis" 2>/dev/null | grep -q '5f00:0:3::/48' &&
  docker exec $L-r3 ip -6 route show 5f00:0:3:dc04::/128 2>/dev/null | grep -q seg6local && break
  sleep 2
done

check "r2 tiene End con flavor PSP"                 "docker exec $L-r2 ip -6 route show 5f00:0:2:e000::/128 | grep -qi 'psp'"
check "r1 encapsula en modo reducido (encap.red)"   "docker exec $L-r1 ip route show 10.0.2.0/24 | grep -q 'encap.red'"
check "r3 tiene el SID End.DX4 (entrega IPv4)"       "docker exec $L-r3 ip -6 route show 5f00:0:3:dc04::/128 | grep -q 'End.DX4'"
check "h1 → h2 IPv6 (plano, por el IGP)"             "docker exec $L-h1 ping -c2 -W2 3fff:0:2::20"
check "h1 → h2 IPv4 sobre SRv6 (10.0.2.20)"          "docker exec $L-h1 ping -c2 -W2 10.0.2.20"
check "h2 → h1 IPv4 sobre SRv6 (vuelta)"             "docker exec $L-h2 ping -c2 -W2 10.0.1.10"

# Captura en los dos tramos del núcleo durante un ping IPv4.
#   r1→r2 (eth1 de r2): debe llevar SRH          → Next Header 43
#   r2→r3 (eth2 de r2): SIN SRH, IPv4 encapsulado → Next Header 4   (lo quitó PSP)
cap_nh() {  # $1 = interfaz en r2, $2 = filtro tcpdump
  docker run --rm --net container:$L-r2 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni "$1" -c1 "$2" >$T/m09_$1.txt 2>&1 &
  sleep 1
  docker exec $L-h1 ping -c3 -W1 10.0.2.20 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/m09_$1.txt
}
echo "Comprobando la reducción de cabecera y PSP en el núcleo..."
check "r1→r2 lleva SRH (encap reducido, 1 SID)"     "cap_nh eth1 'ip6[6]==43'"
check "r2→r3 va SIN SRH: PSP la quitó (IPv4 dentro)" "cap_nh eth2 'ip6[6]==4'"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  docker exec $L-r1 ip route show 10.0.2.0/24
  docker exec $L-r2 ip -6 route show 5f00:0:2:e000::/128
  docker exec $L-h1 ping -c2 -W2 10.0.2.20 2>&1 | tail -3
  echo "--- captura r1→r2 (eth1) ---"; cat $T/m09_eth1.txt 2>/dev/null | head -4
  echo "--- captura r2→r3 (eth2) ---"; cat $T/m09_eth2.txt 2>/dev/null | head -4
fi
