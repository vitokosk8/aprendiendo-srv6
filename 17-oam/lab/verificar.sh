#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 17 (OAM y troubleshooting). Uso: ./verificar.sh
L=clab-m17
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap \'rm -rf "$T"\' EXIT
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS, SRv6 y al servicio (máx. 90 s)..."
for i in $(seq 1 45); do
  docker exec $L-r3 ip -6 route show 5f00:0:3:dc04::/128 2>/dev/null | grep -qi 'End.DX4' &&
  docker exec $L-r1 ip -6 route show 5f00:0:3::/48 2>/dev/null | grep -q . && break
  sleep 2
done

# --- Base: transporte + servicio funcionando ---
check "r1 aprende el locator de r3 por IS-IS"          "docker exec $L-r1 ip -6 route show 5f00:0:3::/48 | grep -q ."
check "FRR instaló el SID End en sr0 (r1)"             "docker exec $L-r1 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "r3 tiene el servicio End.DX4 (manual)"          "docker exec $L-r3 ip -6 route show 5f00:0:3:dc04::/128 | grep -qi 'End.DX4'"
check "h1 → h2 IPv4 sobre SRv6"                        "docker exec $L-h1 ping -c2 -W2 10.0.2.20"
check "h2 → h1 IPv4 sobre SRv6 (vuelta)"               "docker exec $L-h2 ping -c2 -W2 10.0.1.10"

# --- OAM: ping ---
check "ping al loopback de r3 (alcanzabilidad) responde"  "docker exec $L-r1 ping -c2 -W2 3fff:0:ff::3"
check "ping a un SID de decap (End.DX4) NO responde (correcto: espera encap)" "! docker exec $L-r1 ping -c1 -W2 5f00:0:3:dc04::"
check "ping a un SID NO instalado no responde (correcto)" "! docker exec $L-r1 ping -c1 -W2 5f00:0:3:ffff::"

# --- OAM: traceroute llega ---
check "traceroute h1 → h2 completa"                    "docker exec $L-h1 traceroute -n -w1 -q1 -m8 10.0.2.20 2>/dev/null | grep -q '10.0.2.20'"

# --- OAM: captura del tráfico de cliente en el núcleo ---
cap() {
  docker run --rm --net container:$L-r2 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni eth1 -c1 'ip6 and (ip6[6]==43 or ip6[6]==4)' >$T/m16cap.txt 2>&1 &
  sleep 1
  docker exec $L-h1 ping -c3 -W1 10.0.2.20 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/m16cap.txt
}
check "el tráfico de cliente cruza r2 encapsulado en SRv6"  "cap"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  docker exec $L-r1 ip -6 route show 5f00:0:3::/48
  docker exec $L-r3 ip -6 route show | grep seg6local | head
  docker exec $L-r1 ip route get 10.0.2.20 2>&1 | head -2
  docker exec $L-h1 ping -c2 -W2 10.0.2.20 2>&1 | tail -3
  cat $T/m16cap.txt 2>/dev/null | head -3
fi
