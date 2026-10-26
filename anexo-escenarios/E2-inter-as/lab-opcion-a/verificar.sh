#!/usr/bin/env bash
# Comprueba el escenario E2 (dos operadores, Inter-AS L3VPNv4), opción A: VRF contra VRF.
# Cada bloque corresponde a un criterio de éxito del README del escenario. Uso: ./verificar.sh
L=clab-esc-e2-a
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap 'rm -rf "$T"' EXIT
ok=0; fail=0
check() { if ( eval "$2" ) >/dev/null 2>check() { if eval "$2" >/dev/null 2>&1; then1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

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

echo "--- Criterio 1: cada operador tiene su propia L3VPN ---"
check "AS 64500: iBGP VPNv4 r1 ↔ r6 establecida"                "[ \$(docker exec $L-r1 vtysh -c 'show bgp ipv4 vpn summary json' | grep -o '\"state\":\"Established\"' | wc -l) -ge 1 ]"
check "AS 64501: iBGP VPNv4 r7 ↔ r8 establecida"                "[ \$(docker exec $L-r8 vtysh -c 'show bgp ipv4 vpn summary json' | grep -o '\"state\":\"Established\"' | wc -l) -ge 1 ]"
for r in r1 r6 r7 r8; do
  check "$r instaló su SID End.DT4 (VRF BLUE)"                  "docker exec $L-$r ip -6 route show | grep 'End.DT4' | grep -q 'table 10'"
done

echo "--- Criterio 2: los ASBR se tratan como clientes (eBGP IPv4 dentro de la VRF) ---"
check "eBGP r6 ↔ r7 en la VRF BLUE establecida"                 "docker exec $L-r6 vtysh -c 'show bgp vrf BLUE ipv4 unicast summary json' | grep -q '\"state\":\"Established\"'"
check "r6 aprende BLUE-4 (192.168.40.0/24) de r7, sin SRv6"     "docker exec $L-r6 ip route show vrf BLUE 192.168.40.0/24 | grep -q 'via 172.16.67.2' && ! docker exec $L-r6 ip route show vrf BLUE 192.168.40.0/24 | grep -q seg6"

echo "--- Criterio 3: cada SRv6 termina en la frontera de su AS ---"
check "r1 encapsula hacia BLUE-4 con el SID de r6 (su propio ASBR)" "docker exec $L-r1 ip route show vrf BLUE 192.168.40.0/24 | grep -q 'segs 1 \[ 5f00:0:6:'"
check "r8 encapsula hacia BLUE-1 con el SID de r7 (su propio ASBR)" "docker exec $L-r8 ip route show vrf BLUE 192.168.10.0/24 | grep -q 'segs 1 \[ 5f00:1:7:'"
check "el AS 64500 no conoce ningún SID del AS 64501"           "c=\$(docker exec $L-r1 ip -6 route show) && ! echo \"\$c\" | grep -q '5f00:1:'"
echo "Comprobando qué cruza el enlace entre operadores (captura en r6:eth6)..."
check "por el enlace r6–r7 pasa IPv4 sin encapsular"            "cap r6 eth6 'icmp and host 192.168.40.12'"

echo "--- Criterio 4: las sedes de los dos operadores se ven ---"
check "BLUE-1 → BLUE-4 (h1 → h4)"                               "docker exec $L-h1 ping -c2 -W2 192.168.40.12"
check "BLUE-4 → BLUE-1 (h4 → h1)"                               "docker exec $L-h4 ping -c2 -W2 192.168.10.12"

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
