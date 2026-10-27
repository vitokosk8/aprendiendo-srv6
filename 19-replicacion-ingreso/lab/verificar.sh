#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 19 (multicast con replicación en el ingreso). Uso: ./verificar.sh
L=clab-m19
AQUI=$(cd "$(dirname "$0")" && pwd)
HOJAS="$AQUI/replicacion/hojas.txt"
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
cp "$HOJAS" "$T/hojas.txt"
trap 'cp "$T/hojas.txt" "$HOJAS"; rm -rf "$T"' EXIT     # deja hojas.txt como estaba, pase lo que pase
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
  docker exec $L-r1 ip -6 route show 5f00:0:3::/48 2>/dev/null | grep -q via &&
  docker exec $L-r1 ip -6 route show 5f00:0:4::/48 2>/dev/null | grep -q via &&
  docker exec $L-r1 ip -6 route show 5f00:0:5::/48 2>/dev/null | grep -q via && break
  sleep 2
done
# Los receptores arrancan al desplegar; si alguno no está, se arranca ahora
for h in h3 h4 h5; do
  docker exec $L-$h pgrep -x socat >/dev/null 2>&1 || docker exec -d $L-$h socat -u UDP4-RECV:5000,reuseaddr,ip-add-membership=233.252.0.1:eth1 OPEN:/tmp/recibido.txt,creat,append
done
sleep 1

echo "--- Transporte: IS-IS con SRv6 (como en el módulo 11) ---"
for r in r3 r4 r5; do
  check "r1 aprende el locator de $r por IS-IS"          "docker exec $L-r1 ip -6 route show 5f00:0:${r#r}::/48 | grep -q via"
  check "$r tiene su SID de hoja (End.DX4 hacia su receptor)" "docker exec $L-$r ip -6 route show 5f00:0:${r#r}:d4:: | grep -q 'End.DX4'"
done

echo "--- La replicación en el ingreso ---"
check "el replicador está en marcha en r1"              "docker exec $L-r1 pgrep -f replicador.py"
check "los tres receptores están unidos al grupo"       "for h in h3 h4 h5; do docker exec $L-\$h pgrep -x socat || exit 1; done"
check "r1 no tiene enrutamiento multicast (nada de PIM)" "! docker exec $L-r1 ip mroute show | grep -q 233.252.0.1"
enviar "$TOK"
for h in h3 h4 h5; do
  check "$h recibe el datagrama del grupo"               "recibio $h $TOK"
done
check "el replicador registra 3 copias por paquete"     "docker exec $L-r1 grep -q '3 copias (r3 r4 r5)' /tmp/replicador.log"

echo "Comprobando las copias en el cable (capturas)..."
cap r2 eth1 'ip6 and ip6[6] == 4'
check "de r1 a r2 viajan TRES copias del mismo paquete"  "[ \$(grep -c 'IP6' $T/cap_r2_eth1.txt) = 3 ]"
for r in r3 r4 r5; do
  check "  una de ellas hacia el SID de $r"              "grep -q '> 5f00:0:${r#r}:d4::' $T/cap_r2_eth1.txt"
done
check "dentro va el paquete original de h1 al grupo, sin SRH (Next Header 4)" "grep -q '10.0.1.10.* > 233.252.0.1' $T/cap_r2_eth1.txt"
cap r3 eth1 'ip6 and ip6[6] == 4'
check "de r2 a r3 viaja UNA copia (la suya)"            "[ \$(grep -c 'IP6' $T/cap_r3_eth1.txt) = 1 ] && grep -q '> 5f00:0:3:d4::' $T/cap_r3_eth1.txt"

echo "--- Las hojas se pueden cambiar en caliente ---"
sed -i 's/^r5 /# r5 /' "$HOJAS"; sleep 1
TOK2=sin-r5-$RANDOM; enviar "$TOK2"
check "sin r5 en hojas.txt: h3 sigue recibiendo"        "recibio h3 $TOK2"
check "sin r5 en hojas.txt: h5 ya no recibe"            "! recibio h5 $TOK2"
check "el replicador registra 2 copias"                 "docker exec $L-r1 grep -q '2 copias (r3 r4)' /tmp/replicador.log"
cp "$T/hojas.txt" "$HOJAS"; sleep 1
TOK3=con-r5-$RANDOM; enviar "$TOK3"
check "r5 vuelve a la lista: h5 vuelve a recibir"       "recibio h5 $TOK3"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r1: registro del replicador ---"; docker exec $L-r1 tail -15 /tmp/replicador.log 2>&1
  echo "--- r1: rutas a los locators ---"; docker exec $L-r1 ip -6 route show | grep 5f00
  for r in r3 r4 r5; do echo "--- $r: SIDs ---"; docker exec $L-$r ip -6 route show | grep -i seg6local; done
  for h in h3 h4 h5; do echo "--- $h: recibido ---"; docker exec $L-$h tail -3 /tmp/recibido.txt 2>&1; docker exec $L-$h ip maddr show dev eth1 | grep 233; done
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -6 "$f"; }; done
fi
