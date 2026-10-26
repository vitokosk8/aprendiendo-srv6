#!/usr/bin/env bash
# Comprueba el escenario E6 (service chaining con un firewall sin SRv6).
# Cada bloque corresponde a un criterio de éxito del README del escenario. Uso: ./verificar.sh
L=clab-esc-e6
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap 'rm -rf "$T"' EXIT
ok=0; fail=0
check() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi

# Captura en un router mientras h1 hace ping a h2. $1 = router o nodo, $2 = interfaz, $3 = filtro
cap() {
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni "$2" -nn -c1 "$3" >$T/cap_$1_$2.txt 2>&1 &
  sleep 1
  docker exec $L-h1 ping -c3 -W1 192.168.20.12 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/cap_$1_$2.txt
}
# ¿Abre h1 una conexión TCP con h2 en el puerto $1?
tcp() { docker exec $L-h1 timeout 3 bash -c "echo > /dev/tcp/192.168.20.12/$1"; }
# Paquetes que el firewall ha dejado pasar de BLUE-1 a BLUE-2
fwcnt() { docker exec $L-fw iptables -L FORWARD -v -n -x | awk '$3=="ACCEPT" && $8=="192.168.10.0/24" {print $1}'; }

echo "Esperando a IS-IS, BGP y a las rutas de las VRF (máx. 150 s)..."
for i in $(seq 1 75); do
  docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r6 ip route show vrf BLUE 192.168.10.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r4 ip route show vrf FW1 192.168.10.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r4 ip route show vrf FW2 192.168.20.0/24 2>/dev/null | grep -q 'encap seg6' && break
  sleep 2
done

echo "--- Criterio 1: la L3VPN y el proxy SR están montados ---"
for r in r1 r6; do
  check "$r tiene su SID de servicio (End.DT4 de la VRF BLUE)" "docker exec $L-$r ip -6 route show | grep -q 'End.DT4'"
done
check "r4 tiene sus dos sesiones iBGP (con r1 y con r6)" "[ \$(docker exec $L-r4 vtysh -c 'show bgp summary json' | grep -o '\"state\":\"Established\"' | wc -l) -ge 2 ]"
check "r4: SID 5f00:0:4:f1:: = End.DT4 en la VRF FW1 (tabla 20)" "docker exec $L-r4 ip -6 route show 5f00:0:4:f1:: | grep 'End.DT4' | grep -q 'vrftable 20'"
check "r4: SID 5f00:0:4:f2:: = End.DT4 en la VRF FW2 (tabla 21)" "docker exec $L-r4 ip -6 route show 5f00:0:4:f2:: | grep 'End.DT4' | grep -q 'vrftable 21'"

echo "--- Criterio 2: cada VRF del proxy manda al firewall o reencapsula ---"
check "FW1: hacia BLUE-2, al firewall (172.16.41.2)"              "docker exec $L-r4 ip route show vrf FW1 192.168.20.0/24 | grep -q 'via 172.16.41.2'"
check "FW1: hacia BLUE-1, reencapsula hacia un SID de r1 (por BGP)" "docker exec $L-r4 ip route show vrf FW1 192.168.10.0/24 | grep -q 'segs 1 \\[ 5f00:0:1:'"
check "FW2: hacia BLUE-1, al firewall (172.16.42.2)"              "docker exec $L-r4 ip route show vrf FW2 192.168.10.0/24 | grep -q 'via 172.16.42.2'"
check "FW2: hacia BLUE-2, reencapsula hacia un SID de r6 (por BGP)" "docker exec $L-r4 ip route show vrf FW2 192.168.20.0/24 | grep -q 'segs 1 \\[ 5f00:0:6:'"

echo "--- Criterio 3: sin la cadena, el tráfico va directo y no pasa por el firewall ---"
docker exec $L-fw iptables -Z FORWARD >/dev/null 2>&1
check "BLUE-1 → BLUE-2 (ping)"                    "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
check "BLUE-1 → BLUE-2 por TCP 80"                "tcp 80"
check "BLUE-1 → BLUE-2 por TCP 23 (sin firewall, también pasa)" "tcp 23"
check "el firewall no ha visto nada"              "[ \"\$(fwcnt)\" = 0 ]"

echo "--- Criterio 4 (cadena): todo el tráfico entre sedes pasa por el firewall ---"
IDA="ip route 192.168.20.0/24 3fff:0:12::2 eth1 nexthop-vrf default segments 5f00:0:4:f1::"
VUELTA="ip route 192.168.10.0/24 3fff:0:46::4 eth1 nexthop-vrf default segments 5f00:0:4:f2::"
docker exec $L-r1 vtysh -c "configure terminal" -c "vrf BLUE" -c "$IDA" >/dev/null 2>&1
docker exec $L-r6 vtysh -c "configure terminal" -c "vrf BLUE" -c "$VUELTA" >/dev/null 2>&1
sleep 3
check "r1 encapsula hacia BLUE-2 con el SID f1 del proxy"  "docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep -q 'segs 1 \\[ 5f00:0:4:f1:: \\]'"
check "r6 encapsula hacia BLUE-1 con el SID f2 del proxy"  "docker exec $L-r6 ip route show vrf BLUE 192.168.10.0/24 | grep -q 'segs 1 \\[ 5f00:0:4:f2:: \\]'"
check "BLUE-1 → BLUE-2 (ping, ida y vuelta por el firewall)" "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
check "BLUE-2 → BLUE-1 (ping)"                     "docker exec $L-h2 ping -c2 -W2 192.168.10.12"
check "TCP 80: permitido"                          "tcp 80"
check "TCP 23: bloqueado por el firewall"          "! tcp 23"
check "el firewall ha contado el tráfico de BLUE-1 a BLUE-2" "[ \"\$(fwcnt)\" -gt 0 ]"
echo "Comprobando el camino en el cable (capturas)..."
check "en r2, hacia r4: destino el SID f1, encapsulado" "cap r2 eth3 'ip6 and dst host 5f00:0:4:f1::'"
check "entre r4 y el firewall: IPv4 sin SRv6"          "cap fw eth1 'icmp and src 192.168.10.12 and dst 192.168.20.12'"
check "de r4 a r6: reencapsulado hacia el SID de r6"   "cap r6 eth1 'ip6 and dst net 5f00:0:6::/48'"
check "de r6 a r4 (vuelta): destino el SID f2"         "cap r4 eth3 'ip6 and dst host 5f00:0:4:f2::'"
docker exec $L-r1 vtysh -c "configure terminal" -c "vrf BLUE" -c "no $IDA" >/dev/null 2>&1
docker exec $L-r6 vtysh -c "configure terminal" -c "vrf BLUE" -c "no $VUELTA" >/dev/null 2>&1
sleep 3
check "sin las estáticas, r1 vuelve a la ruta de BGP (directo a r6)" "docker exec $L-r1 ip route show vrf BLUE 192.168.20.0/24 | grep -q 'segs 1 \\[ 5f00:0:6:'"
check "y TCP 23 vuelve a pasar"                    "tcp 23"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r4: SIDs (seg6local) ---"; docker exec $L-r4 ip -6 route show | grep -i seg6local
  for v in FW1 FW2; do echo "--- r4: kernel VRF $v ---"; docker exec $L-r4 ip route show vrf $v; done
  echo "--- r1 / r6: kernel VRF BLUE ---"; docker exec $L-r1 ip route show vrf BLUE; docker exec $L-r6 ip route show vrf BLUE
  echo "--- r4: BGP ---"; docker exec $L-r4 vtysh -c "show bgp summary" 2>&1 | tail -8
  echo "--- r4: rutas BGP de FW1/FW2 ---"; docker exec $L-r4 vtysh -c "show ip route vrf all" 2>&1 | grep -v '^$' | tail -25
  echo "--- fw ---"; docker exec $L-fw ip route; docker exec $L-fw iptables -L FORWARD -v -n -x
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -4 "$f"; }; done
fi
