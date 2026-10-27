#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 20 (segmentos de replicación, RFC 9524). Uso: ./verificar.sh
L=clab-m20
AQUI=$(cd "$(dirname "$0")" && pwd)
R2="$AQUI/replicacion/estado/r2.txt"
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
cp "$R2" "$T/r2.txt"
trap 'cp "$T/r2.txt" "$R2"; rm -rf "$T"' EXIT        # deja el estado de r2 como estaba, pase lo que pase
ok=0; fail=0
check() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi

# Envía un datagrama al grupo desde h1. $1 = texto
enviar() { docker exec $L-h1 bash -c "echo $1 | socat -u - UDP4-DATAGRAM:233.252.0.1:5000,ip-multicast-ttl=8"; }
# ¿Ha recibido el host $1 el texto $2?
recibio() { for i in 1 2 3 4 5; do docker exec $L-$1 grep -q "$2" /tmp/recibido.txt 2>/dev/null && return 0; sleep 1; done; return 1; }
# Captura en un router mientras h1 envía un datagrama. $1 = router, $2 = interfaz, $3 = filtro
cap() {
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 5 tcpdump -ni "$2" -nn "$3" >$T/cap_$1_$2.txt 2>&1 &
  for i in $(seq 1 50); do grep -q 'listening on' $T/cap_$1_$2.txt 2>/dev/null && break; sleep 0.1; done
  enviar "captura-$RANDOM"
  wait
}
TOK=prueba-$RANDOM

echo "Esperando a IS-IS y a las rutas de los locators (máx. 120 s)..."
for i in $(seq 1 60); do
  docker exec $L-r1 ip -6 route show 5f00:0:2::/48 2>/dev/null | grep -q via &&
  docker exec $L-r2 ip -6 route show 5f00:0:3::/48 2>/dev/null | grep -q via &&
  docker exec $L-r2 ip -6 route show 5f00:0:4::/48 2>/dev/null | grep -q via &&
  docker exec $L-r2 ip -6 route show 5f00:0:5::/48 2>/dev/null | grep -q via && break
  sleep 2
done
for h in h3 h4 h5; do
  docker exec $L-$h pgrep -x socat >/dev/null 2>&1 || docker exec -d $L-$h socat -u UDP4-RECV:5000,reuseaddr,ip-add-membership=233.252.0.1:eth1 OPEN:/tmp/recibido.txt,creat,append
done
sleep 1

echo "--- El árbol: un segmento de replicación en cada nodo ---"
check "r1 (raíz) aprende el locator de r2 por IS-IS"     "docker exec $L-r1 ip -6 route show 5f00:0:2::/48 | grep -q via"
check "r1 (raíz): su segmento de replicación está en marcha"  "docker exec $L-r1 pgrep -f 'replicacion.py r1'"
check "r2 (nodo): su segmento de replicación está en marcha"  "docker exec $L-r2 pgrep -f 'replicacion.py r2'"
check "r2: el kernel descarta en silencio el Replication-SID (blackhole)" "docker exec $L-r2 ip -6 route show 5f00:0:2:a1:: | grep -q blackhole"
for r in r3 r4 r5; do
  check "$r (hoja): su Replication-SID es un End.DX4"     "docker exec $L-$r ip -6 route show 5f00:0:${r#r}:a1:: | grep -q 'End.DX4'"
done

echo "--- El tráfico baja por el árbol ---"
check "los tres receptores están unidos al grupo"       "for h in h3 h4 h5; do docker exec $L-\$h pgrep -x socat || exit 1; done"
enviar "$TOK"
for h in h3 h4 h5; do
  check "$h recibe el datagrama del grupo"               "recibio $h $TOK"
done
check "r1 hace UNA copia (hacia r2)"                    "docker exec $L-r1 grep -q '1 copia (r2)' /tmp/replicacion.log"
check "r2 hace TRES copias (hacia r3, r4 y r5)"         "docker exec $L-r2 grep -q '3 copias (r3 r4 r5)' /tmp/replicacion.log"

echo "Comprobando las copias en el cable (capturas)..."
cap r2 eth1 'ip6 and ip6[6] == 4'
check "de r1 a r2 viaja UNA sola copia (en el módulo 19 eran tres)" "[ \$(grep -c 'IP6' $T/cap_r2_eth1.txt) = 1 ]"
check "  hacia el Replication-SID de r2"                 "grep -q '> 5f00:0:2:a1::' $T/cap_r2_eth1.txt"
cap r3 eth1 'ip6 and ip6[6] == 4'
check "de r2 a r3 viaja una copia hacia el Replication-SID de r3" "[ \$(grep -c 'IP6' $T/cap_r3_eth1.txt) = 1 ] && grep -q '> 5f00:0:3:a1::' $T/cap_r3_eth1.txt"
check "  r2 solo ha reescrito el destino: el origen sigue siendo r1" "grep -q '3fff:0:12::1 > 5f00:0:3:a1::' $T/cap_r3_eth1.txt"
check "  y dentro va el paquete original de h1 al grupo" "grep -q '10.0.1.10.* > 233.252.0.1' $T/cap_r3_eth1.txt"

echo "--- El estado de replicación se puede cambiar ---"
sed -i 's/^rama r5 /# rama r5 /' "$R2"; sleep 1
TOK2=sin-r5-$RANDOM; enviar "$TOK2"
check "sin la rama r5 en r2: h3 sigue recibiendo"       "recibio h3 $TOK2"
check "sin la rama r5 en r2: h5 ya no recibe"           "! recibio h5 $TOK2"
check "r1 no se ha enterado: sigue haciendo una copia"  "[ \$(docker exec $L-r1 grep -c '1 copia (r2)' /tmp/replicacion.log) -ge 3 ]"
cp "$T/r2.txt" "$R2"; sleep 1
TOK3=con-r5-$RANDOM; enviar "$TOK3"
check "la rama r5 vuelve: h5 vuelve a recibir"          "recibio h5 $TOK3"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  for r in r1 r2; do echo "--- $r: registro del segmento de replicación ---"; docker exec $L-$r tail -12 /tmp/replicacion.log 2>&1; done
  echo "--- r2: rutas a los locators y al Replication-SID ---"; docker exec $L-r2 ip -6 route show | grep 5f00
  for r in r3 r4 r5; do echo "--- $r: SIDs ---"; docker exec $L-$r ip -6 route show | grep -i seg6local; done
  for h in h3 h4 h5; do echo "--- $h: recibido ---"; docker exec $L-$h tail -3 /tmp/recibido.txt 2>&1; done
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -6 "$f"; }; done
fi
