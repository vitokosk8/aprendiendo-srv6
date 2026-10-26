#!/usr/bin/env bash
# Comprueba el escenario E1 (cliente multisede: L3VPNv4 con route reflector y UCMP).
# Cada bloque corresponde a un criterio de éxito del README del escenario. Uso: ./verificar.sh
L=clab-esc-e1
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap 'rm -rf "$T"' EXIT
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi

echo "Esperando a IS-IS, BGP y a las rutas de las tres sedes (máx. 150 s)..."
for i in $(seq 1 75); do
  docker exec $L-r1 ip -6 route show 2>/dev/null | grep -q 'End.DT4' &&
  docker exec $L-r5 ip -6 route show 2>/dev/null | grep -q 'End.DT4' &&
  docker exec $L-r6 ip -6 route show 2>/dev/null | grep -q 'End.DT4' &&
  docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r1 ip route show vrf BLUE 192.168.30.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r6 ip route show vrf BLUE 192.168.30.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r5 ip route show vrf BLUE 192.168.10.0/24 2>/dev/null | grep -q 'encap seg6' && break
  sleep 2
done

est() { docker exec $L-$1 vtysh -c 'show bgp ipv4 vpn summary json' 2>/dev/null | grep -o '"state":"Established"' | wc -l; }

echo "--- Transporte (IS-IS + SRv6, como en la topología base) ---"
check "r1 aprende los locators de r5 y r6 por IS-IS"     "docker exec $L-r1 ip -6 route show 5f00:0:5::/48 | grep -q via && docker exec $L-r1 ip -6 route show 5f00:0:6::/48 | grep -q via"

echo "--- Criterio 1: cada PE tiene una sola sesión iBGP, con el route reflector ---"
for r in r1 r5 r6; do
  check "$r: exactamente 1 sesión iBGP establecida (con r2)" "[ \$(est $r) -eq 1 ] && docker exec $L-$r vtysh -c 'show bgp ipv4 vpn summary' | grep -q '^3fff:0:ff::2 '"
done
check "r2 (route reflector): 3 sesiones establecidas"    "[ \$(est r2) -eq 3 ]"

echo "--- Criterio 2: cada PE tiene su SID de servicio ---"
for r in r1 r5 r6; do
  check "$r instaló su SID End.DT4 (VRF BLUE)"           "docker exec $L-$r ip -6 route show | grep 'End.DT4' | grep -q 'table 10'"
done

echo "--- Criterio 3: cada sede conoce las otras dos, a través del route reflector ---"
check "r1 aprende BLUE-2 (192.168.20.0/24) con encapsulado SRv6 hacia r6" "docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep -q 'segs 1 \[ 5f00:0:6:'"
check "r1 aprende BLUE-3 (192.168.30.0/24) con encapsulado SRv6 hacia r5" "docker exec $L-r1 ip route show vrf BLUE 192.168.30.0/24 | grep -q 'segs 1 \[ 5f00:0:5:'"
check "r6 aprende BLUE-3 con encapsulado SRv6 hacia r5"                   "docker exec $L-r6 ip route show vrf BLUE 192.168.30.0/24 | grep -q 'segs 1 \[ 5f00:0:5:'"
check "r5 aprende BLUE-1 con encapsulado SRv6 hacia r1"                   "docker exec $L-r5 ip route show vrf BLUE 192.168.10.0/24 | grep -q 'segs 1 \[ 5f00:0:1:'"
check "la ruta de BLUE-2 en r1 viene reflejada (originador r6, cluster r2)" "docker exec $L-r1 vtysh -c 'show bgp vrf BLUE ipv4 unicast 192.168.20.0/24' | grep -q 'Originator: 10.255.0.6' && docker exec $L-r1 vtysh -c 'show bgp vrf BLUE ipv4 unicast 192.168.20.0/24' | grep -qi 'cluster list: 10.255.0.2'"

echo "--- Criterio 4: el route reflector está fuera del camino de los datos ---"
check "r2 no tiene la VRF BLUE"                           "! docker exec $L-r2 ip link show BLUE"
check "r2 no tiene ningún SID End.DT4"                    "c=\$(docker exec $L-r2 ip -6 route show) && ! echo \"\$c\" | grep -q 'End.DT4'"
check "r2 no instala rutas de BLUE en su kernel"          "c=\$(docker exec $L-r2 ip route show 192.168.20.0/24) && [ -z \"\$c\" ]"
check "r3 y r4 siguen sin BGP"                            "for r in r3 r4; do c=\$(docker exec $L-\$r vtysh -c 'show running-config') || exit 1; echo \"\$c\" | grep -q '^router bgp' && exit 1; done; true"

echo "--- Criterio 5: las tres sedes se ven entre sí ---"
check "BLUE-1 → BLUE-2 (h1 → h2)"                         "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
check "BLUE-1 → BLUE-3 (h1 → h3)"                         "docker exec $L-h1 ping -c2 -W2 192.168.30.12"
check "BLUE-2 → BLUE-3 (h2 → h3)"                         "docker exec $L-h2 ping -c2 -W2 192.168.30.12"

echo "--- Criterio 6 (TE): r1 reparte el tráfico hacia BLUE-2 por dos caminos, 3:1 (UCMP) ---"
SID=$(docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep -o '5f00:0:6:[0-9a-f:]*' | head -1)
echo "  (SID End.DT4 de r6 para BLUE: ${SID:-no encontrado})"
ARRIBA="ip route 192.168.20.0/24 3fff:0:12::2 eth1 nexthop-vrf default weight 3 segments 5f00:0:4::/$SID"
ABAJO="ip route 192.168.20.0/24 3fff:0:13::3 eth2 nexthop-vrf default weight 1 segments 5f00:0:5::/$SID"
txb() { docker exec $L-r1 cat /sys/class/net/$1/statistics/tx_bytes; }
if [ -n "$SID" ]; then
  docker exec $L-r1 vtysh -c "configure terminal" -c "vrf BLUE" -c "$ARRIBA" -c "$ABAJO" >/dev/null 2>&1
  sleep 3
  # zebra normaliza los pesos 3:1 a la escala del kernel: 255 y 85
  check "la ruta a BLUE-2 es ahora estática con dos caminos (pesos 255 y 85, es decir, 3:1)" "docker exec $L-r1 vtysh -c 'show ip route vrf BLUE 192.168.20.0/24' | grep -q 'Known via \"static\"' && docker exec $L-r1 vtysh -c 'show ip route vrf BLUE 192.168.20.0/24' | grep -q 'weight 255' && docker exec $L-r1 vtysh -c 'show ip route vrf BLUE 192.168.20.0/24' | grep -q 'weight 85'"
  check "en el kernel, cada camino lleva 2 segmentos"     "[ \$(docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep -c 'segs 2') -ge 2 ]"
  check "con UCMP, BLUE-1 → BLUE-2 sigue funcionando"     "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
  echo "  Enviando 32 flujos TCP de h1 a h2 (iperf3, 4 s) y midiendo por dónde salen de r1..."
  a0=$(txb eth1); b0=$(txb eth2)
  docker exec $L-h1 iperf3 -c 192.168.20.12 -P 32 -t 4 -M 1300 >$T/iperf.txt 2>&1
  a1=$(txb eth1); b1=$(txb eth2)
  da=$((a1 - a0)); db=$((b1 - b0))
  echo "  bytes enviados por r1: arriba (eth1, hacia r2) $da · abajo (eth2, hacia r3) $db"
  check "los dos caminos llevan tráfico"                 "[ $da -gt 100000 ] && [ $db -gt 100000 ]"
  check "el camino de peso 3 lleva más que el de peso 1" "[ $da -gt $db ]"
  docker exec $L-r1 vtysh -c "configure terminal" -c "vrf BLUE" -c "no $ARRIBA" -c "no $ABAJO" >/dev/null 2>&1
  sleep 3
  check "sin las estáticas, se vuelve a la ruta de BGP (1 segmento)" "docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep -q 'segs 1'"
else
  check "r1 conoce el SID de r6 para montar las rutas UCMP" "false"
fi

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r2: BGP summary ---";               docker exec $L-r2 vtysh -c "show bgp ipv4 vpn summary" 2>&1 | tail -6
  echo "--- r1: BGP VRF BLUE ---";             docker exec $L-r1 vtysh -c "show bgp vrf BLUE ipv4 unicast" 2>&1 | tail -8
  echo "--- r1: ruta a BLUE-2 (detalle) ---";  docker exec $L-r1 vtysh -c "show bgp vrf BLUE ipv4 unicast 192.168.20.0/24" 2>&1 | head -20
  for r in r1 r5 r6; do echo "--- $r: SIDs de servicio ---"; docker exec $L-$r ip -6 route show | grep -i 'End.DT'; done
  echo "--- r1: kernel VRF BLUE ---";          docker exec $L-r1 ip route show vrf BLUE
  echo "--- iperf3 (resumen) ---";             tail -4 $T/iperf.txt 2>/dev/null
fi
