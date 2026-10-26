#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 14 (ingeniería de tráfico con SRv6). Uso: ./verificar.sh
L=clab-m14
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap \'rm -rf "$T"\' EXIT
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS, SRv6 y a las rutas (máx. 90 s)..."
for i in $(seq 1 45); do
  docker exec $L-r1 ip -6 route show 5f00:0:4::/48 2>/dev/null | grep -q . &&
  docker exec $L-r3 ip -6 route show 5f00:0:3:e000::/128 2>/dev/null | grep -q seg6local && break
  sleep 2
done

# --- Transporte y SIDs ---
check "FRR instaló SIDs de transporte en r2 (End/End.X)" "docker exec $L-r2 ip -6 route show | grep -qi 'seg6local action End'"
check "r3 tiene el waypoint End (5f00:0:3:e000::)"        "docker exec $L-r3 ip -6 route show 5f00:0:3:e000::/128 | grep -qi 'action End'"
check "r4 tiene el servicio End.DX4 (5f00:0:4:dc04::)"    "docker exec $L-r4 ip -6 route show 5f00:0:4:dc04::/128 | grep -qi 'End.DX4'"

# --- El IGP ve el camino corto por r2 ---
check "El camino más corto IGP a r4 va por r2 (eth2)"     "docker exec $L-r1 ip -6 route show 5f00:0:4::/48 | grep -q 'dev eth2'"

# --- La TE fuerza el camino largo por r3 ---
check "r1 fuerza el tráfico de cliente por r3 (lista de 2 SIDs)" "docker exec $L-r1 ip route show 10.0.2.0/24 | grep -q '5f00:0:3:e000::'"

# Captura: el tráfico de cliente debe cruzar r3 (TE) y NO r2 (corto)
cap() {  # $1 = router, $2 = iface
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni "$2" -nn -c1 'ip6 and dst net 5f00::/16' >$T/m14_$1.txt 2>&1 &
  sleep 1
  docker exec $L-h1 ping -c3 -W1 10.0.2.20 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/m14_$1.txt
}
echo "Comprobando por dónde va el tráfico (debe ser r3, no r2)..."
check "el tráfico de cliente CRUZA r3 (camino TE)"        "cap r3 eth1"
check "el tráfico de cliente NO cruza r2 (camino corto)"  "! cap r2 eth1"

# --- Conectividad de cliente ---
check "h1 → h2 (IPv4, por el camino forzado)"             "docker exec $L-h1 ping -c2 -W2 10.0.2.20"
check "h2 → h1 (vuelta)"                                  "docker exec $L-h2 ping -c2 -W2 10.0.1.10"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r1: ruta de cliente (TE) ---"   ; docker exec $L-r1 ip route show 10.0.2.0/24
  echo "--- r1: camino IGP a r4 ---"        ; docker exec $L-r1 ip -6 route show 5f00:0:4::/48
  echo "--- r3: waypoint ---"               ; docker exec $L-r3 ip -6 route show 5f00:0:3:e000::/128
  echo "--- captura r3 ---"                 ; cat $T/m14_r3.txt 2>/dev/null | head -3
  echo "--- captura r2 ---"                 ; cat $T/m14_r2.txt 2>/dev/null | head -3
  docker exec $L-h1 ping -c2 -W2 10.0.2.20 2>&1 | tail -3
fi
