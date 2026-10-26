#!/usr/bin/env bash
# Comprueba el escenario E4 (network slicing: dos rebanadas con SLA distinto).
# Cada bloque corresponde a un criterio de éxito del README del escenario. Uso: ./verificar.sh
L=clab-esc-e4
AQUI=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap 'rm -rf "$T"' EXIT
ok=0; fail=0
check() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi

# Captura en un router mientras un host hace ping. $1 = router, $2 = interfaz, $3 = filtro, $4 = host, $5 = destino
cap() {
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni "$2" -nn -c1 "$3" >$T/cap_$1_$2.txt 2>&1 &
  sleep 1
  docker exec $L-$4 ping -c3 -W1 $5 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/cap_$1_$2.txt
}
# RTT medio (ms, entero) de un ping. $1 = host, $2 = destino
rtt() { docker exec $L-$1 ping -c5 -i0.2 -W2 $2 | sed -n 's/.*= [0-9.]*\/\([0-9.]*\)\/.*/\1/p' | cut -d. -f1; }
sid() { docker exec $L-$1 ip -6 route show | awk -v t="vrftable $2" '/End.DT4/ && index($0, t) {print $1; exit}'; }

echo "Esperando a IS-IS, BGP y a las rutas de las dos rebanadas (máx. 150 s)..."
for i in $(seq 1 75); do
  docker exec $L-r1 ip route show vrf ORO 192.168.20.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r1 ip route show vrf PLATA 192.168.120.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r6 ip route show vrf ORO 192.168.10.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r6 ip route show vrf PLATA 192.168.110.0/24 2>/dev/null | grep -q 'encap seg6' && break
  sleep 2
done
"$AQUI/rebanadas.sh" retardo 10 >/dev/null
"$AQUI/rebanadas.sh" desactivar >/dev/null 2>&1   # por si quedaron activas de otra ejecución
sleep 2
R6ORO=$(sid r6 10); R6PLATA=$(sid r6 11)

echo "--- Criterio 1: dos rebanadas, cada una con su VRF y su SID de servicio ---"
for r in r1 r6; do
  check "$r: End.DT4 de ORO (tabla 10)"   "[ -n \"\$(sid $r 10)\" ]"
  check "$r: End.DT4 de PLATA (tabla 11)" "[ -n \"\$(sid $r 11)\" ]"
  check "$r: son SIDs distintos"          "[ \"\$(sid $r 10)\" != \"\$(sid $r 11)\" ]"
done
check "ORO-1 → ORO-2"                     "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
check "PLATA-1 → PLATA-2"                 "docker exec $L-h11 ping -c2 -W2 192.168.120.12"
check "ORO no ve a PLATA"                 "! docker exec $L-h1 ping -c2 -W1 192.168.120.12"
check "PLATA no ve a ORO"                 "! docker exec $L-h11 ping -c2 -W1 192.168.20.12"

echo "--- Criterio 2: sin rebanadas, las dos comparten el camino más corto ---"
check "r1 → r6 para PLATA: un solo SID, el de r6 (BGP)" "docker exec $L-r1 ip route show vrf PLATA 192.168.120.0/24 | grep -q 'segs 1 \\[ $R6PLATA \\]'"
check "el tráfico de PLATA pasa por r2 (el camino de ORO)" "cap r2 eth1 'ip6 and dst host $R6PLATA' h11 192.168.120.12"
check "las dos con latencia baja (RTT < 10 ms)"  "[ \$(rtt h1 192.168.20.12) -lt 10 ] && [ \$(rtt h11 192.168.120.12) -lt 10 ]"

echo "--- Criterio 3: con rebanadas, cada una por su camino y con su SLA ---"
"$AQUI/rebanadas.sh" activar >/dev/null 2>&1
sleep 3
check "ORO: r1 encapsula por r4 (End de r4 + SID de ORO de r6)"     "docker exec $L-r1 ip route show vrf ORO 192.168.20.0/24 | grep -q 'segs 2 \\[ 5f00:0:4:: $R6ORO \\]'"
check "PLATA: r1 encapsula por r5 (End de r5 + SID de PLATA de r6)" "docker exec $L-r1 ip route show vrf PLATA 192.168.120.0/24 | grep -q 'segs 2 \\[ 5f00:0:5:: $R6PLATA \\]'"
check "ORO-1 → ORO-2"                     "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
check "PLATA-1 → PLATA-2"                 "docker exec $L-h11 ping -c2 -W2 192.168.120.12"
check "ORO sigue con latencia baja (RTT < 10 ms)"   "[ \$(rtt h1 192.168.20.12) -lt 10 ]"
check "PLATA va por el enlace largo (RTT >= 15 ms)" "[ \$(rtt h11 192.168.120.12) -ge 15 ]"
echo "Comprobando el aislamiento en el cable (capturas)..."
check "ORO pasa por r2 → r4"                          "cap r2 eth3 'ip6 and dst host 5f00:0:4::' h1 192.168.20.12"
check "PLATA pasa por r3 → r5"                        "cap r3 eth3 'ip6 and dst host 5f00:0:5::' h11 192.168.120.12"
check "PLATA ya no sale de r1 hacia r2"               "! cap r2 eth1 'ip6 and (dst host 5f00:0:5:: or dst host $R6PLATA)' h11 192.168.120.12"
"$AQUI/rebanadas.sh" desactivar >/dev/null 2>&1
sleep 3
check "sin las estáticas, PLATA vuelve al camino más corto" "docker exec $L-r1 ip route show vrf PLATA 192.168.120.0/24 | grep -q 'segs 1 \\[ $R6PLATA \\]'"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  "$AQUI/rebanadas.sh" estado 2>&1
  echo "--- r1: BGP ---"; docker exec $L-r1 vtysh -c "show bgp summary" 2>&1 | tail -6
  echo "--- retardo en r3 eth3 ---"; docker run --rm --net container:$L-r3 nicolaka/netshoot:v0.13 tc qdisc show dev eth3
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -4 "$f"; }; done
fi
