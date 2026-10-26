#!/usr/bin/env bash
# Comprueba el escenario E0 (Internet sobre SRv6), parte 2: Internet en la tabla global.
# Cada comprobación corresponde a un criterio de éxito del README del escenario. Uso: ./verificar.sh
L=clab-esc-e0-global
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap 'rm -rf "$T"' EXIT
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi

echo "Esperando a IS-IS, BGP y a las rutas de Internet (máx. 150 s)..."
for i in $(seq 1 75); do
  docker exec $L-r1 ip -6 route show 2>/dev/null | grep -q 'End.DT46' &&
  docker exec $L-r6 ip -6 route show 2>/dev/null | grep -q 'End.DT46' &&
  docker exec $L-r1 ip route show 198.51.100.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r1 ip -6 route show 3fff:198:51:100::/64 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-inet ip route show 203.0.113.0/24 2>/dev/null | grep -q via &&
  docker exec $L-inet ip -6 route show 3fff:203:0:113::/64 2>/dev/null | grep -q via && break
  sleep 2
done

# Captura en un router mientras h1 hace ping al servidor web. $1 = router, $2 = interfaz, $3 = filtro
cap() {
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 6 tcpdump -ni "$2" -nn -c1 "$3" >$T/cap_$1.txt 2>&1 &
  sleep 1
  docker exec $L-h1 ping -c3 -W1 198.51.100.10 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/cap_$1.txt
}

echo "--- Transporte (IS-IS + SRv6, como en la topología base) ---"
check "r1 aprende el locator de r6 (5f00:0:6::/48) por IS-IS" "docker exec $L-r1 ip -6 route show 5f00:0:6::/48 | grep -q via"
check "camino más corto hacia r6: sale por r2 (eth1)"        "docker exec $L-r1 ip -6 route show 5f00:0:6::/48 | grep -q 'dev eth1'"

echo "--- Criterio 1: el operador recibe Internet por r6 ---"
check "eBGP r6 ↔ upstream (IPv4) establecida"                 "docker exec $L-inet vtysh -c 'show bgp ipv4 unicast summary json' | grep -q '\"state\":\"Established\"'"
check "eBGP r6 ↔ upstream (IPv6) establecida"                 "docker exec $L-inet vtysh -c 'show bgp ipv6 unicast summary json' | grep -q '\"state\":\"Established\"'"
check "iBGP r1 ↔ r6 (ipv4 unicast) establecida"                   "docker exec $L-r1 vtysh -c 'show bgp ipv4 unicast summary json' | grep -q '\"state\":\"Established\"'"

echo "--- Criterio 2: cada PE tiene su SID de servicio ---"
check "r1 instaló su SID End.DT46 (tabla global)"  "docker exec $L-r1 ip -6 route show | grep -q 'End.DT46'"
check "r6 instaló su SID End.DT46 (tabla global)"  "docker exec $L-r6 ip -6 route show | grep -q 'End.DT46'"

echo "--- Criterio 3: r1 llega a Internet encapsulando en SRv6 hacia r6 ---"
check "r1: ruta a 198.51.100.0/24 con encapsulado SRv6"       "docker exec $L-r1 ip route show 198.51.100.0/24 | grep -q 'encap seg6'"
check "r1: ruta a 3fff:198:51:100::/64 con encapsulado SRv6"  "docker exec $L-r1 ip -6 route show 3fff:198:51:100::/64 | grep -q 'encap seg6'"
check "el SID de destino es de r6 (5f00:0:6:…)"               "docker exec $L-r1 ip route show 198.51.100.0/24 | grep -q '5f00:0:6:'"

echo "--- Criterio 4: Internet conoce el bloque del cliente ---"
check "el upstream aprende 203.0.113.0/24"                    "docker exec $L-inet ip route show 203.0.113.0/24 | grep -q via"
check "el upstream aprende 3fff:203:0:113::/64"               "docker exec $L-inet ip -6 route show 3fff:203:0:113::/64 | grep -q via"

echo "--- Criterio 5: núcleo sin BGP y sin rutas de Internet ---"
check "ningún P (r2–r5) tiene BGP configurado"                "for r in r2 r3 r4 r5; do c=\$(docker exec $L-\$r vtysh -c 'show running-config') || exit 1; echo \"\$c\" | grep -q '^router bgp' && exit 1; done; true"
check "ningún P (r2–r5) conoce 198.51.100.0/24"               "for r in r2 r3 r4 r5; do c=\$(docker exec $L-\$r ip route show 198.51.100.0/24) || exit 1; [ -n \"\$c\" ] && exit 1; done; true"
check "ningún P (r2–r5) conoce 3fff:198:51:100::/64"          "for r in r2 r3 r4 r5; do c=\$(docker exec $L-\$r ip -6 route show 3fff:198:51:100::/64) || exit 1; [ -n \"\$c\" ] && exit 1; done; true"

echo "--- Criterio 6: el cliente navega (IPv4 e IPv6) ---"
check "h1 → web por IPv4"                                     "docker exec $L-h1 ping -c2 -W2 198.51.100.10"
check "h1 → web por IPv6"                                     "docker exec $L-h1 ping -c2 -W2 3fff:198:51:100::10"
check "web → h1 por IPv4 (vuelta)"                            "docker exec $L-web ping -c2 -W2 203.0.113.12"
check "web → h1 por IPv6 (vuelta)"                            "docker exec $L-web ping -c2 -W2 3fff:203:0:113::12"
echo "Comprobando que el tráfico cruza el núcleo encapsulado (captura en r2)..."
check "en r2 el ping viaja dentro de SRv6 hacia r6"           "cap r2 eth1 'ip6 and dst net 5f00:0:6::/48'"

echo "--- Criterio 7 (TE): el tráfico hacia 198.51.100.0/24 puede forzarse por r3 y r5 ---"
SID=$(docker exec $L-r1 ip route show 198.51.100.0/24 | grep -o '5f00:0:6:[0-9a-f:]*' | head -1)
echo "  (SID End.DT46 de r6 anunciado por BGP: ${SID:-no encontrado})"
te_on()  { docker exec $L-r1 vtysh -c "configure terminal" -c "ip route 198.51.100.0/24 3fff:0:13::3 eth2 segments 5f00:0:5::/$SID"; sleep 3; }
te_off() { docker exec $L-r1 vtysh -c "configure terminal" -c "no ip route 198.51.100.0/24 3fff:0:13::3 eth2 segments 5f00:0:5::/$SID"; sleep 3; }
if [ -n "$SID" ]; then
  te_on
  check "con la ruta estática TE, la ruta lleva 2 segmentos (r5, r6)" "docker exec $L-r1 ip route show 198.51.100.0/24 | grep -q 'segs 2'"
  check "con TE, el ping pasa por r3 hacia el End de r5"             "cap r3 eth1 'ip6 and dst host 5f00:0:5::'"
  check "con TE, h1 → web sigue funcionando"                         "docker exec $L-h1 ping -c2 -W2 198.51.100.10"
  te_off
  check "sin la estática, se vuelve al camino BGP (1 segmento)"      "docker exec $L-r1 ip route show 198.51.100.0/24 | grep -q 'segs 1'"
else
  check "r1 conoce el SID de r6 para montar la ruta TE" "false"
fi

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r1: BGP summary ---";        docker exec $L-r1 vtysh -c "show bgp ipv4 unicast summary" 2>&1 | tail -5
  echo "--- r6: BGP summary ---";        docker exec $L-r6 vtysh -c "show bgp ipv4 unicast summary" 2>&1 | tail -6
  echo "--- r6: BGP SRv6 ---";           docker exec $L-r6 vtysh -c "show bgp segment-routing srv6" 2>&1 | tail -14
  echo "--- r1: SIDs seg6local ---";     docker exec $L-r1 ip -6 route show | grep -i seg6local
  echo "--- r6: SIDs seg6local ---";     docker exec $L-r6 ip -6 route show | grep -i seg6local
  echo "--- r1: ruta a 198.51.100.0/24 ---"; docker exec $L-r1 vtysh -c "show ip route 198.51.100.0/24" 2>&1
  echo "--- r1: kernel ---";             docker exec $L-r1 ip route show 198.51.100.0/24
  echo "--- inet: ruta al cliente ---";  docker exec $L-inet vtysh -c "show ip route 203.0.113.0/24" 2>&1 | head -8
  echo "--- strict_mode r1/r6 ---";      docker exec $L-r1 sysctl net.vrf.strict_mode; docker exec $L-r6 sysctl net.vrf.strict_mode
  echo "--- h1 → web ---";               docker exec $L-h1 ping -c2 -W2 198.51.100.10 2>&1 | tail -3
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -4 "$f"; }; done
fi
