#!/usr/bin/env bash
# Comprueba el escenario E7 (controlador con BGP-LS). Uso: ./verificar.sh
# Cada bloque corresponde a un criterio de éxito del README del escenario. Necesita python3 en esta máquina.
L=clab-esc-e7
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
command -v python3 >/dev/null || { echo "❌ Hace falta python3 en esta máquina para ejecutar el controlador."; exit 1; }

# Captura en un router mientras un host hace ping. $1 = router, $2 = interfaz, $3 = filtro, $4 = host, $5 = destino
cap() {
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 8 tcpdump -ni "$2" -nn -c1 "$3" >$T/cap_$1_$2.txt 2>&1 &
  # espera a que tcpdump esté escuchando (arrancar el contenedor puede tardar más de un segundo)
  for i in $(seq 1 50); do grep -q 'listening on' $T/cap_$1_$2.txt 2>/dev/null && break; sleep 0.1; done
  docker exec $L-$4 ping -c3 -W1 $5 >/dev/null 2>&1
  wait
  grep -q '1 packet captured' $T/cap_$1_$2.txt
}
sid() { docker exec $L-$1 ip -6 route show | awk -v t="vrftable $2" '/End.DT4/ && index($0, t) {print $1; exit}'; }
# Cuenta las NLRI de BGP-LS de un tipo (node, link, srv6Sid, ipv6Prefix) que tiene ctl
nlri() { docker exec $L-ctl vtysh -c "show bgp link-state link-state json" > $T/ls.json 2>/dev/null
         python3 -c "import json,sys; r=json.load(open('$T/ls.json')).get('routes',{}); print(sum(1 for v in r.values() if v[0]['nlri']['nlriType']=='$1'))" 2>/dev/null || echo 0; }
# Atributo de la NLRI del enlace $1 -> $2 (por nombre de router)
enlace() { docker exec $L-ctl vtysh -c "show bgp link-state link-state json" > $T/ls.json 2>/dev/null
           python3 - "$T/ls.json" "$1" "$2" "$3" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))['routes']
num = lambda d: 'r%d' % int(d['igpRouterId'].split('.')[2])
for v in r.values():
    n = v[0]['nlri']
    if n['nlriType'] == 'link' and num(n['localNodeDescriptors']) == sys.argv[2] and num(n['remoteNodeDescriptors']) == sys.argv[3]:
        print(json.dumps(v[0].get('linkStateAttrs', {}).get(sys.argv[4]))); break
PY
}
ruta() { docker exec $L-$1 ip route show vrf $2 $3; }
esperar_enlaces() { for i in $(seq 1 45); do [ "$(nlri link)" = "$1" ] && return 0; sleep 2; done; return 1; }

echo "Esperando a IS-IS, BGP, BGP-LS y a las rutas de las rebanadas (máx. 150 s)..."
for i in $(seq 1 75); do
  [ "$(nlri link)" = 20 ] &&
  docker exec $L-r1 ip route show vrf ORO 192.168.20.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r1 ip route show vrf PLATA 192.168.120.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r6 ip route show vrf ORO 192.168.10.0/24 2>/dev/null | grep -q 'encap seg6' &&
  docker exec $L-r6 ip route show vrf PLATA 192.168.110.0/24 2>/dev/null | grep -q 'encap seg6' && break
  sleep 2
done
"$AQUI/controlador.py" --limpiar >/dev/null 2>&1    # por si quedaron estáticas de otra ejecución
R6ORO=$(sid r6 10); R6PLATA=$(sid r6 11); R1ORO=$(sid r1 10); R1PLATA=$(sid r1 11)

echo "--- Criterio 1: el controlador ve la topología SRv6 por BGP-LS ---"
check "sesión BGP-LS entre ctl y r2 establecida"     "docker exec $L-ctl vtysh -c 'show bgp neighbor 3fff:0:c2::2 json' | grep -q '\"bgpState\":\"Established\"'"
check "ctl conoce los 6 routers (NLRI de nodo)"      "[ \$(nlri node) = 6 ]"
check "ctl conoce los 10 enlaces, en los dos sentidos (20 NLRI de enlace)" "[ \$(nlri link) = 20 ]"
check "ctl conoce los SIDs de nodo (NLRI SRv6 SID)"   "[ \$(nlri srv6Sid) -ge 6 ]"
check "enlace r3 → r5: métrica IGP 10"               "[ \"\$(enlace r3 r5 igpMetric)\" = 10 ]"
check "enlace r3 → r5: retardo 2000 µs"              "[ \"\$(enlace r3 r5 delay)\" = 2000 ]"
check "enlace r2 → r5: trae su End.X"                "enlace r2 r5 srv6EndxSids | grep -q '5f00:0:2:'"

echo "--- Criterio 2: el controlador programa cada servicio por su camino ---"
check "controlador.py se ejecuta sin errores"        "\"$AQUI/controlador.py\" > $T/ctl1.txt 2>&1"
check "ORO (r1 → r6): por r3 y r5 (menor retardo): End de r5 y el SID de r6" "ruta r1 ORO 192.168.20.0/24 | grep -q 'segs 2 \\[ 5f00:0:5:: $R6ORO \\]'"
check "PLATA (r1 → r6): por r2, el camino IGP sin enlaces de ORO (solo el SID de r6)" "ruta r1 PLATA 192.168.120.0/24 | grep -q 'segs 1 \\[ $R6PLATA \\]'"
check "ORO (r6 → r1): por r5 y r3: End de r3 y el SID de r1" "ruta r6 ORO 192.168.10.0/24 | grep -q 'segs 2 \\[ 5f00:0:3:: $R1ORO \\]'"
check "PLATA (r6 → r1): por r4 (solo el SID de r1)"  "ruta r6 PLATA 192.168.110.0/24 | grep -q 'segs 1 \\[ $R1PLATA \\]'"
check "ORO-1 → ORO-2"                                "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
check "PLATA-1 → PLATA-2"                            "docker exec $L-h11 ping -c2 -W2 192.168.120.12"
check "en el cable: ORO pasa por r3 → r5 (hacia el End de r5)" "cap r3 eth3 'ip6 and dst host 5f00:0:5::' h1 192.168.20.12"
check "en el cable: ORO sale de r5 hacia r6 con el SID de r6"   "cap r6 eth2 'ip6 and dst host $R6ORO' h1 192.168.20.12"
check "en el cable: PLATA pasa por r2 → r4"          "cap r2 eth3 'ip6 and dst host $R6PLATA' h11 192.168.120.12"

echo "--- Criterio 3: cae el enlace r3-r5 y el controlador reprograma ---"
docker exec $L-r3 ip link set eth3 down; docker exec $L-r5 ip link set eth1 down
check "BGP-LS retira el enlace (quedan 18 NLRI de enlace)" "esperar_enlaces 18"
check "controlador.py recalcula sin errores"         "\"$AQUI/controlador.py\" > $T/ctl2.txt 2>&1"
check "ORO (r1 → r6): ahora por r2, con el End.X de r2 hacia r5 y el SID de r6" "ruta r1 ORO 192.168.20.0/24 | grep -q 'segs 2 \\[ 5f00:0:2:[0-9a-f:]* $R6ORO \\]'"
check "PLATA (r1 → r6): ahora por r3: End de r3 y el SID de r6" "ruta r1 PLATA 192.168.120.0/24 | grep -q 'segs 2 \\[ 5f00:0:3:: $R6PLATA \\]'"
check "PLATA (r6 → r1): End de r3 y el SID de r1"    "ruta r6 PLATA 192.168.110.0/24 | grep -q 'segs 2 \\[ 5f00:0:3:: $R1PLATA \\]'"
check "ORO-1 → ORO-2"                                "docker exec $L-h1 ping -c2 -W2 192.168.20.12"
check "PLATA-1 → PLATA-2"                            "docker exec $L-h11 ping -c2 -W2 192.168.120.12"
check "en el cable: ORO sale de r2 hacia r5 por el End.X" "cap r5 eth4 'ip6 and dst host $R6ORO' h1 192.168.20.12"

echo "--- Criterio 4: vuelve el enlace y el controlador deshace el cambio ---"
docker exec $L-r3 ip link set eth3 up; docker exec $L-r5 ip link set eth1 up
check "BGP-LS vuelve a anunciar el enlace (20 NLRI)" "esperar_enlaces 20"
check "controlador.py recalcula sin errores"         "\"$AQUI/controlador.py\" > $T/ctl3.txt 2>&1"
check "ORO (r1 → r6) vuelve por r3 y r5"             "ruta r1 ORO 192.168.20.0/24 | grep -q 'segs 2 \\[ 5f00:0:5:: $R6ORO \\]'"
"$AQUI/controlador.py" --limpiar >/dev/null 2>&1
sleep 2
check "--limpiar quita las estáticas: ORO vuelve a la ruta de BGP" "! docker exec $L-r1 vtysh -c 'show running-config' | grep -q 'ip route 192.168.20.0/24' && ruta r1 ORO 192.168.20.0/24 | grep -q 'segs 1 \\[ $R6ORO \\]'"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  for f in $T/ctl1.txt $T/ctl2.txt $T/ctl3.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; cat "$f"; }; done
  echo "--- ctl: resumen BGP-LS ---"; docker exec $L-ctl vtysh -c "show bgp link-state link-state" 2>&1 | head -40
  echo "--- ctl: un enlace en JSON ---"
  docker exec $L-ctl vtysh -c "show bgp link-state link-state json" 2>/dev/null | python3 -c "
import json,sys; r=json.load(sys.stdin).get('routes',{})
l=[v[0] for v in r.values() if v[0]['nlri']['nlriType']=='link'][:1]; print(json.dumps(l, indent=1))" 2>&1 | head -60
  echo "--- r1: VRF ORO y PLATA ---"; docker exec $L-r1 ip route show vrf ORO; docker exec $L-r1 ip route show vrf PLATA
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -4 "$f"; }; done
fi
