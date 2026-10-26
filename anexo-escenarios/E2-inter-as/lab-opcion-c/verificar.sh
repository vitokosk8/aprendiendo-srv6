#!/usr/bin/env bash
# Comprueba el escenario E2 (dos operadores, Inter-AS L3VPNv4), opción C con SRv6.
# Cada bloque corresponde a un criterio de éxito del README del escenario. Uso: ./verificar.sh
L=clab-esc-e2-c
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap 'rm -rf "$T"' EXIT
ok=0; fail=0
check() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi

echo "Esperando a IS-IS, BGP y a las rutas entre los dos operadores (máx. 150 s)..."
for i in $(seq 1 75); do
  docker exec $L-r1 ip -6 route show 2>/dev/null | grep -q 'End.DT4' &&
  docker exec $L-r8 ip -6 route show 2>/dev/null | grep -q 'End.DT4' &&
  docker exec $L-r1 ip route show vrf BLUE 192.168.40.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r8 ip route show vrf BLUE 192.168.10.0/24 2>/dev/null | grep -q 'encap seg6' && break
  sleep 2
done

# Captura en un router mientras h1 hace ping a h4. $1 = router, $2 = interfaz, $3 = filtro
cap() {
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni "$2" -nn -c1 "$3" >$T/cap_$1_$2.txt 2>&1 &
  sleep 1
  docker exec $L-h1 ping -c3 -W1 192.168.40.12 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/cap_$1_$2.txt
}

echo "--- Transporte: cada AS tiene su IS-IS y su SRv6 ---"
check "AS 64500: r1 aprende el locator de r6 (5f00:0:6::/48)"   "docker exec $L-r1 ip -6 route show 5f00:0:6::/48 | grep -q via"
check "AS 64501: r8 aprende el locator de r7 (5f00:1:7::/48)"   "docker exec $L-r8 ip -6 route show 5f00:1:7::/48 | grep -q via"

echo "--- Criterio 1: los ASBR intercambian solo los bloques de cada AS ---"
check "eBGP IPv6 r6 ↔ r7 establecida"                           "[ \$(docker exec $L-r6 vtysh -c 'show bgp ipv6 unicast summary json' | grep -o '\"state\":\"Established\"' | wc -l) -ge 1 ]"
check "r6 aprende el bloque de SIDs del AS 64501 (5f00:1::/32)" "docker exec $L-r6 ip -6 route show 5f00:1::/32 | grep 'proto bgp' | grep -q 'dev eth6'"
check "r7 aprende el bloque de SIDs del AS 64500 (5f00:0::/32)" "docker exec $L-r7 ip -6 route show 5f00:0::/32 | grep 'proto bgp' | grep -q 'dev eth1'"
check "los ASBR no tienen VRF ni SIDs de servicio"              "for r in r6 r7; do docker exec $L-\$r ip link show BLUE >/dev/null 2>&1 && exit 1; c=\$(docker exec $L-\$r ip -6 route show) || exit 1; echo \"\$c\" | grep -q 'End.DT' && exit 1; done; true"

echo "--- Criterio 2: cada IGP aprende el otro AS con UNA ruta por bloque ---"
check "r1 aprende 5f00:1::/32 por IS-IS (redistribuido por r6)" "docker exec $L-r1 ip -6 route show 5f00:1::/32 | grep -q 'proto isis'"
check "r1 aprende las loopbacks del AS 64501 (3fff:1:ff::/48)"  "docker exec $L-r1 ip -6 route show 3fff:1:ff::/48 | grep -q 'proto isis'"
check "r8 aprende 5f00:0::/32 por IS-IS (redistribuido por r7)" "docker exec $L-r8 ip -6 route show 5f00:0::/32 | grep -q 'proto isis'"
check "un P (r3) ve todo el AS 64501 como una sola ruta"        "[ \$(docker exec $L-r3 ip -6 route show | grep -c '^5f00:1:') -eq 1 ]"

echo "--- Criterio 3: los PE de los dos AS hablan VPNv4 directamente ---"
check "eBGP multisalto VPNv4 r1 ↔ r8 establecida"               "[ \$(docker exec $L-r1 vtysh -c 'show bgp ipv4 vpn summary json' | grep -o '\"state\":\"Established\"' | wc -l) -ge 1 ]"
for r in r1 r8; do
  check "$r instaló su SID End.DT4 (VRF BLUE)"                  "docker exec $L-$r ip -6 route show | grep 'End.DT4' | grep -q 'table 10'"
done

echo "--- Criterio 4: un solo túnel SRv6 de punta a punta ---"
check "r1 encapsula hacia BLUE-4 con el SID de r8 (el PE del otro AS)" "docker exec $L-r1 ip route show vrf BLUE 192.168.40.0/24 | grep -q 'segs 1 \[ 5f00:1:8:'"
check "r8 encapsula hacia BLUE-1 con el SID de r1"              "docker exec $L-r8 ip route show vrf BLUE 192.168.10.0/24 | grep -q 'segs 1 \[ 5f00:0:1:'"
echo "Comprobando qué cruza el enlace entre operadores (captura en r6:eth6)..."
check "por el enlace r6–r7 pasa SRv6 hacia el SID de r8"        "cap r6 eth6 'ip6 and dst net 5f00:1:8::/48'"

echo "--- Criterio 5: las sedes de los dos operadores se ven ---"
check "BLUE-1 → BLUE-4 (h1 → h4)"                               "docker exec $L-h1 ping -c2 -W2 192.168.40.12"
check "BLUE-4 → BLUE-1 (h4 → h1)"                               "docker exec $L-h4 ping -c2 -W2 192.168.10.12"

echo "--- Criterio 6 (TE): r1 lleva el tráfico de BLUE-4 por abajo (r3, r5) dentro de su AS ---"
SID=$(docker exec $L-r1 ip route show vrf BLUE 192.168.40.0/24 | grep -o '5f00:1:8:[0-9a-f:]*' | head -1)
echo "  (SID End.DT4 de r8 para BLUE: ${SID:-no encontrado})"
TE="ip route 192.168.40.0/24 3fff:0:13::3 eth2 nexthop-vrf default segments 5f00:0:5::/$SID"
if [ -n "$SID" ]; then
  docker exec $L-r1 vtysh -c "configure terminal" -c "vrf BLUE" -c "$TE" >/dev/null 2>&1; sleep 3
  check "la ruta a BLUE-4 lleva 2 segmentos: r5 (AS 64500) y r8 (AS 64501)" "docker exec $L-r1 ip route show vrf BLUE 192.168.40.0/24 | grep -q 'segs 2 \[ 5f00:0:5:: 5f00:1:8:'"
  check "con TE, el tráfico pasa por r3 hacia el End de r5"     "cap r3 eth1 'ip6 and dst host 5f00:0:5::'"
  check "con TE, BLUE-1 → BLUE-4 sigue funcionando"             "docker exec $L-h1 ping -c2 -W2 192.168.40.12"
  docker exec $L-r1 vtysh -c "configure terminal" -c "vrf BLUE" -c "no $TE" >/dev/null 2>&1; sleep 3
  check "sin la estática, se vuelve a la ruta de BGP (1 segmento)" "docker exec $L-r1 ip route show vrf BLUE 192.168.40.0/24 | grep -q 'segs 1'"
else
  check "r1 conoce el SID de r8 para montar la ruta TE" "false"
fi

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  for r in r1 r6 r7 r8; do echo "--- $r: BGP ---"; docker exec $L-$r vtysh -c "show bgp summary" 2>&1 | grep -v '^$' | tail -8; done
  for r in r1 r6 r7 r8; do echo "--- $r: SIDs de servicio ---"; docker exec $L-$r ip -6 route show | grep -i 'End.DT'; done
  echo "--- r1: kernel VRF BLUE ---"; docker exec $L-r1 ip route show vrf BLUE
  echo "--- r8: kernel VRF BLUE ---"; docker exec $L-r8 ip route show vrf BLUE
  echo "--- r1: rutas IPv6 del otro AS ---"; docker exec $L-r1 ip -6 route show | grep -E '5f00:1|3fff:1'
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -4 "$f"; }; done
fi
