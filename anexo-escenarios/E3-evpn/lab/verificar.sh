#!/usr/bin/env bash
# Comprueba el escenario E3 (EVPN sobre SRv6: el plano de datos de un VPWS con End.DX2).
# Cada bloque corresponde a un criterio de éxito del README del escenario. Uso: ./verificar.sh
L=clab-esc-e3
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap 'rm -rf "$T"' EXIT
ok=0; fail=0
check() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi

SCRIPTS="$(cd "$(dirname "$0")" && pwd)/scripts"
# Ejecuta scripts/l2.py en el espacio de red de un PE. $1 = r1 o r6; el resto, argumentos de l2.py
pe() { local r=$1; shift; docker run --rm --net container:$L-$r -v "$SCRIPTS:/lab:ro" nicolaka/netshoot:v0.13 python3 /lab/l2.py "$@"; }
# Captura en un contenedor mientras se ejecuta una acción. $1 = contenedor, $2 = interfaz, $3 = filtro, $4… = acción
cap() {
  local c=$1 i=$2 f=$3; shift 3
  docker run --rm --net container:$L-$c nicolaka/netshoot:v0.13 timeout 8 tcpdump -ni "$i" -nn -c1 "$f" >$T/cap_${c}_$i.txt 2>&1 &
  sleep 1; "$@" >/dev/null 2>&1; wait
  grep -q '1 packet captured' $T/cap_${c}_$i.txt
}

echo "Esperando a IS-IS y SRv6 (máx. 90 s)..."
for i in $(seq 1 45); do
  docker exec $L-r1 ip -6 route show 5f00:0:6::/48 2>/dev/null | grep -q via &&
  docker exec $L-r6 ip -6 route show 5f00:0:1::/48 2>/dev/null | grep -q via && break
  sleep 2
done
docker pull -q nicolaka/netshoot:v0.13 >/dev/null 2>&1
H11=$(docker exec $L-h11 cat /sys/class/net/eth1/address)
H12=$(docker exec $L-h12 cat /sys/class/net/eth1/address)
echo "  (MAC de h11: $H11 · MAC de h12: $H12)"
docker exec $L-h11 ip neigh flush dev eth1 >/dev/null 2>&1
docker exec $L-h12 ip neigh flush dev eth1 >/dev/null 2>&1

echo "--- Transporte (IS-IS + SRv6, como en la topología base) ---"
check "r1 aprende el locator de r6 (5f00:0:6::/48)"            "docker exec $L-r1 ip -6 route show 5f00:0:6::/48 | grep -q via"

echo "--- Criterio 1: cada PE tiene su SID End.DX2 hacia el circuito de la sede ---"
check "r1: 5f00:0:1:d2:: es End.DX2 con salida por eth4"       "docker exec $L-r1 ip -6 route show 5f00:0:1:d2:: | grep -q 'End.DX2 oif eth4'"
check "r6: 5f00:0:6:d2:: es End.DX2 con salida por eth4"       "docker exec $L-r6 ip -6 route show 5f00:0:6:d2:: | grep -q 'End.DX2 oif eth4'"
check "los circuitos de las sedes (eth4) no tienen IP"         "for r in r1 r6; do c=\$(docker exec $L-\$r ip -4 addr show eth4) || exit 1; echo \"\$c\" | grep -q inet && exit 1; done; true"

echo "--- Criterio 2: una trama de la sede 1 llega intacta a la sede 2 ---"
check "una petición ARP de h11, encapsulada en r1, aparece en h12 con la MAC de h11" \
      "cap h12 eth1 'arp and ether src $H11' pe r1 arp 5f00:0:6:d2:: $H11 192.168.100.11 192.168.100.12"
check "h12 la procesa: aprende la MAC de h11 en su tabla ARP" "docker exec $L-h12 ip neigh show 192.168.100.11 | grep -qi '$H11'"
check "en el núcleo (r2) viaja dentro de SRv6 hacia el End.DX2 de r6" \
      "cap r2 eth1 'ip6 and dst host 5f00:0:6:d2::' pe r1 arp 5f00:0:6:d2:: $H11 192.168.100.11 192.168.100.12"

echo "--- Criterio 3: también en sentido contrario ---"
check "una petición ARP de h12, encapsulada en r6, aparece en h11" \
      "cap h11 eth1 'arp and ether src $H12' pe r6 arp 5f00:0:1:d2:: $H12 192.168.100.12 192.168.100.11"
check "h11 aprende la MAC de h12"                              "docker exec $L-h11 ip neigh show 192.168.100.12 | grep -qi '$H12'"

echo "--- Criterio 4: también viaja tráfico IP, sin que los PE miren las direcciones ---"
check "un ping de h11 encapsulado en r1 llega a h12, y h12 responde (la respuesta sale hacia r6)" \
      "cap r6 eth4 'icmp and icmp[icmptype] = icmp-echoreply and src host 192.168.100.12' pe r1 ping 5f00:0:6:d2:: $H11 192.168.100.11 $H12 192.168.100.12"
check "ni r1 ni r6 tienen rutas hacia 192.168.100.0/24"        "for r in r1 r6; do c=\$(docker exec $L-\$r ip route show 192.168.100.0/24) || exit 1; [ -n \"\$c\" ] && exit 1; done; true"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  for r in r1 r6; do echo "--- $r: SIDs ---"; docker exec $L-$r ip -6 route show | grep -i seg6local; done
  for r in r1 r6; do echo "--- $r: eth4 ---"; docker exec $L-$r ip -br link show eth4; done
  echo "--- prueba de envío desde r1 ---"; pe r1 arp 5f00:0:6:d2:: $H11 192.168.100.11 192.168.100.12 2>&1 | tail -3
  echo "--- h12: vecinos ---"; docker exec $L-h12 ip neigh show
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -5 "$f"; }; done
fi
