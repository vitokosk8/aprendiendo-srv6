#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 21 (BIER). Uso: ./verificar.sh   (necesita python3)
L=clab-m21
AQUI=$(cd "$(dirname "$0")" && pwd)
ENTRADA="$AQUI/bier/entrada-r1.txt"
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
cp "$ENTRADA" "$T/entrada.txt"
trap 'cp "$T/entrada.txt" "$ENTRADA"; rm -rf "$T"' EXIT     # deja entrada-r1.txt como estaba
ok=0; fail=0
check() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

if ! docker inspect $L-r1 >/dev/null 2>&1; then
  echo "❌ El laboratorio no está desplegado (no existe el contenedor $L-r1)."
  echo "   Despliégalo primero:  sudo containerlab deploy -t lab.clab.yml"
  exit 1
fi
command -v python3 >/dev/null || { echo "❌ Hace falta python3 en esta máquina."; exit 1; }

enviar() { docker exec $L-h1 bash -c "echo $1 | socat -u - UDP4-DATAGRAM:233.252.0.1:5000,ip-multicast-ttl=8"; }
recibio() { for i in 1 2 3 4 5; do docker exec $L-$1 grep -q "$2" /tmp/recibido.txt 2>/dev/null && return 0; sleep 1; done; return 1; }
bift() { docker exec $L-$1 cat /tmp/bift.txt 2>/dev/null; }
# Captura (con el contenido en hexadecimal) en un router mientras h1 envía un datagrama
cap() {
  docker run --rm --net container:$L-$1 nicolaka/netshoot:v0.13 \
    timeout 5 tcpdump -ni "$2" -nn -x 'ip6 proto 253' >$T/cap_$1_$2.txt 2>&1 &
  for i in $(seq 1 50); do grep -q 'listening on' $T/cap_$1_$2.txt 2>/dev/null && break; sleep 0.1; done
  enviar "captura-$RANDOM"
  wait
}
npaq() { grep -c 'IP6' $T/cap_$1_$2.txt; }
# El BitString del primer paquete capturado (bytes 52-59: tras 40 de IPv6 y 12 de cabecera BIER)
bitstring() { python3 - "$T/cap_$1_$2.txt" <<'PY'
import re, sys
h = ''
for l in open(sys.argv[1]):
    m = re.match(r'\s+0x([0-9a-f]{4}):\s+(.*)', l)
    if m:
        if m.group(1) == '0000' and h: break
        h += ''.join(m.group(2).split()[:8])
b = bytes.fromhex(h)
print(hex(int.from_bytes(b[52:60], 'big')) if len(b) >= 60 else 'corto')
PY
}
TOK=prueba-$RANDOM

echo "Esperando a IS-IS y a que cada router calcule su BIFT (máx. 150 s)..."
for i in $(seq 1 75); do
  docker exec $L-r1 ip -6 route show 3fff:0:ff::6 2>/dev/null | grep -q via &&
  [ "$(bift r2 | wc -l)" -ge 3 ] && [ "$(bift r5 | wc -l)" -ge 2 ] && bift r1 | grep -q '{3,4,5,6}' && break
  sleep 2
done
for h in h3 h4 h5 h6; do
  docker exec $L-$h pgrep -x socat >/dev/null 2>&1 || docker exec -d $L-$h socat -u UDP4-RECV:5000,reuseaddr,ip-add-membership=233.252.0.1:eth1 OPEN:/tmp/recibido.txt,creat,append
done
sleep 1

echo "--- El dominio BIER: un router BIER en cada nodo y su BIFT, sacada de IS-IS ---"
for r in r1 r2 r3 r4 r5 r6; do
  check "$r: bier.py en marcha"                          "docker exec $L-$r pgrep -f 'bier.py $r'"
done
check "r1 (BFIR): una sola entrada, F-BM {3,4,5,6} hacia r2" "bift r1 | grep -q 'F-BM {3,4,5,6}.*por eth2'"
check "r2: F-BM {3} por eth2 (r3)"                      "bift r2 | grep -q 'F-BM {3} .*por eth2'"
check "r2: F-BM {4} por eth3 (r4)"                      "bift r2 | grep -q 'F-BM {4} .*por eth3'"
check "r2: F-BM {5,6} por eth4 (r5): r6 se alcanza por r5" "bift r2 | grep -q 'F-BM {5,6} .*por eth4'"
check "r5: F-BM {6} por eth3 (r6)"                      "bift r5 | grep -q 'F-BM {6} .*por eth3'"

echo "--- El tráfico llega a todos los BFER, una vez ---"
check "los cuatro receptores están unidos al grupo"     "for h in h3 h4 h5 h6; do docker exec $L-\$h pgrep -x socat || exit 1; done"
enviar "$TOK"
for h in h3 h4 h5 h6; do
  check "$h recibe el datagrama"                         "recibio $h $TOK"
done
check "h5 lo recibe una sola vez"                       "[ \$(docker exec $L-h5 grep -c $TOK /tmp/recibido.txt) = 1 ]"
check "r1 (BFIR): 1 copia con los bits {3,4,5,6}"       "docker exec $L-r1 grep -q '1 copia · eth2 {3,4,5,6}' /tmp/bier.log"
check "r2: 3 copias, cada una con sus bits"             "docker exec $L-r2 grep -q '3 copias · eth2 {3} · eth3 {4} · eth4 {5,6}' /tmp/bier.log"
check "r5: entrega local y 1 copia con {6} hacia r6"    "docker exec $L-r5 grep -q '1 copia · local → 10.0.5.50 · eth3 {6}' /tmp/bier.log"

echo "Comprobando el BitString en el cable (capturas)..."
cap r2 eth1
check "r1 → r2: un paquete BIER, BitString {3,4,5,6} (0x3c)" "[ \$(npaq r2 eth1) = 1 ] && [ \$(bitstring r2 eth1) = 0x3c ]"
cap r5 eth1
check "r2 → r5: un paquete BIER, BitString {5,6} (0x30)"     "[ \$(npaq r5 eth1) = 1 ] && [ \$(bitstring r5 eth1) = 0x30 ]"
cap r6 eth1
check "r5 → r6: un paquete BIER, BitString {6} (0x20)"       "[ \$(npaq r6 eth1) = 1 ] && [ \$(bitstring r6 eth1) = 0x20 ]"

echo "--- Cambiar los receptores solo toca el BFIR ---"
bift r2 > $T/bift_r2_antes.txt
sed -i 's/^grupo 233.252.0.1 r3 r4 r5 r6/grupo 233.252.0.1 r3 r5 r6/' "$ENTRADA"; sleep 1
TOK2=sin-r4-$RANDOM; enviar "$TOK2"
check "sin r4 en el BFIR: h3 sigue recibiendo"          "recibio h3 $TOK2"
check "sin r4 en el BFIR: h4 ya no recibe"              "! recibio h4 $TOK2"
cap r2 eth1
check "r1 → r2: BitString {3,5,6} (0x34)"               "[ \$(bitstring r2 eth1) = 0x34 ]"
check "la BIFT de r2 no ha cambiado: el núcleo no guarda estado por grupo" "bift r2 | diff -q - $T/bift_r2_antes.txt"
cp "$T/entrada.txt" "$ENTRADA"; sleep 1
TOK3=con-r4-$RANDOM; enviar "$TOK3"
check "r4 vuelve: h4 vuelve a recibir"                  "recibio h4 $TOK3"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  for r in r1 r2 r5; do echo "--- $r: BIFT ---"; bift $r; echo "--- $r: registro ---"; docker exec $L-$r tail -8 /tmp/bier.log 2>&1; done
  echo "--- r2: rutas a los BFR-prefix ---"; docker exec $L-r2 ip -6 route show | grep 'ff::'
  for h in h3 h4 h5 h6; do echo "--- $h: recibido ---"; docker exec $L-$h tail -3 /tmp/recibido.txt 2>&1; done
  for f in $T/cap_*.txt; do [ -f "$f" ] && { echo "--- $(basename $f) ---"; head -8 "$f"; }; done
fi
