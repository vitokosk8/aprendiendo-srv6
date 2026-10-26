#!/usr/bin/env bash
# Comprueba el escenario E5 (compresión uSID y migración), parte 1: toda la red con uSID.
# Cada bloque corresponde a un criterio de éxito del README del escenario. Uso: ./verificar.sh
L=clab-esc-e5-usid
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap 'rm -rf "$T"' EXIT
ok=0; fail=0
check() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi

# Captura en un router mientras h1 hace ping a h2. $1 = router, $2 = interfaz, $3 = filtro
cap() {
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni "$2" -nn -c1 "$3" >$T/cap_$1_$2.txt 2>&1 &
  sleep 1
  docker exec $L-h1 ping -c3 -W1 192.168.20.12 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/cap_$1_$2.txt
}

echo "Esperando a IS-IS, BGP y a las rutas de la VPN (máx. 150 s)..."
for i in $(seq 1 75); do
  docker exec $L-r1 ip -6 route show 2>/dev/null | grep -q 'End.DT46' &&
  docker exec $L-r6 ip -6 route show 2>/dev/null | grep -q 'End.DT46' &&
  docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r1 ip -6 route show vrf BLUE 3fff:168:20::/64 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r6 ip route show vrf BLUE 192.168.10.0/24 2>/dev/null | grep -q 'encap seg6' && break
  sleep 2
done

echo "--- Criterio 1: IS-IS instala los uSID de transporte ---"
for r in r1 r2 r3 r4 r5 r6; do
  check "$r: uN de su locator (End con flavor next-csid)"       "docker exec $L-$r ip -6 route show | grep 'action End ' | grep -q 'next-csid'"
done
check "r2: uA de sus adyacencias (End.X con flavor next-csid)" "docker exec $L-r2 ip -6 route show | grep 'End.X' | grep -q 'next-csid'"

echo "--- Criterio 2: los PE tienen un uDT46 para la VRF BLUE ---"
for r in r1 r6; do
  check "$r instaló su SID de servicio (End.DT46, tabla 10)"    "docker exec $L-$r ip -6 route show | grep 'End.DT46' | grep -q 'table 10'"
  check "$r: BGP lo asignó como uDT46"                          "docker exec $L-$r vtysh -c 'show segment-routing srv6 sid' | grep -q 'uDT46'"
done

echo "--- Criterio 3: la L3VPN dual-stack funciona, sin SRH ---"
check "r1 encapsula hacia BLUE-2 (IPv4) con H.Encaps.Red y un SID de r6" "docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep 'encap.red' | grep -q 'segs 1 \\[ 5f00:0:6:'"
check "r1 encapsula hacia BLUE-2 (IPv6) igual"                 "docker exec $L-r1 ip -6 route show vrf BLUE 3fff:168:20::/64 | grep 'encap.red' | grep -q 'segs 1 \\[ 5f00:0:6:'"
check "r6 encapsula hacia BLUE-1 con un SID de r1"             "docker exec $L-r6 ip route show vrf BLUE 192.168.10.0/24 | grep -q 'segs 1 \\[ 5f00:0:1:'"
check "BLUE-1 → BLUE-2 por IPv4"                               "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
check "BLUE-1 → BLUE-2 por IPv6"                               "docker exec $L-h1 ping -c2 -W2 3fff:168:20::12"
check "BLUE-2 → BLUE-1 por IPv4 (vuelta)"                      "docker exec $L-h2 ping -c2 -W2 192.168.10.12"
check "BLUE-2 → BLUE-1 por IPv6 (vuelta)"                      "docker exec $L-h2 ping -c2 -W2 3fff:168:10::12"
echo "Comprobando la cabecera en el núcleo (captura en r2)..."
check "en r2 el paquete va hacia r6 SIN SRH (Next Header 4: IPv4 dentro)" "cap r2 eth1 'ip6 and dst net 5f00:0:6::/48 and ip6[6] == 4'"

SID=$(docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep -o '5f00:0:6:[0-9a-f:]*' | head -1)
echo "  (SID de servicio de r6 para BLUE: ${SID:-no encontrado})"

echo "--- Criterio 4 (TE): el camino entero cabe en una sola dirección (contenedor uSID) ---"
CONT=$(echo "$SID" | sed 's/^5f00:0:6:/5f00:0:5:6:/')
echo "  (contenedor: uN de r5 + uSID de servicio de r6 = $CONT)"
TE="ip route 192.168.20.0/24 3fff:0:13::3 eth2 nexthop-vrf default segments $CONT encap-behavior H_Encaps_Red"
if [ -n "$SID" ]; then
  docker exec $L-r1 vtysh -c "configure terminal" -c "vrf BLUE" -c "$TE" >/dev/null 2>&1; sleep 3
  check "la ruta TE lleva UN solo SID: el contenedor, sin SRH"      "docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep 'encap.red' | grep -q 'segs 1 \\[ $CONT \\]'"
  check "de r1 a r5 (en r3) el destino es el contenedor, sin SRH"   "cap r3 eth1 'ip6 and dst host $CONT and ip6[6] == 4'"
  check "de r5 a r6 (en r6) el destino ya es el SID de r6: r5 desplazó su uSID" "cap r6 eth2 'ip6 and dst host $SID and ip6[6] == 4'"
  check "con TE, BLUE-1 → BLUE-2 sigue funcionando"                "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
  docker exec $L-r1 vtysh -c "configure terminal" -c "vrf BLUE" -c "no $TE" >/dev/null 2>&1; sleep 3
  check "sin la estática, se vuelve a la ruta de BGP"              "docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep -q 'segs 1 \\[ $SID \\]'"
else
  check "r1 conoce el SID de r6 para montar el contenedor" "false"
fi

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  for r in r1 r2 r6; do echo "--- $r: SIDs (seg6local) ---"; docker exec $L-$r ip -6 route show | grep -i seg6local; done
  echo "--- r1: kernel VRF BLUE ---"; docker exec $L-r1 ip route show vrf BLUE; docker exec $L-r1 ip -6 route show vrf BLUE
  echo "--- r6: kernel VRF BLUE ---"; docker exec $L-r6 ip route show vrf BLUE
  echo "--- r1: BGP SRv6 ---"; docker exec $L-r1 vtysh -c "show bgp segment-routing srv6" 2>&1 | tail -14
  echo "--- r1: locators ---"; docker exec $L-r1 vtysh -c "show segment-routing srv6 locator" 2>&1
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -4 "$f"; }; done
fi
