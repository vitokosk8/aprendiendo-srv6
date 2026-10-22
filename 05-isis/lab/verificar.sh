#!/usr/bin/env bash
# Comprueba que el laboratorio del módulo 05 funciona. Uso: ./verificar.sh
L=clab-m05
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a que IS-IS converja (máx. 60 s)..."
for i in $(seq 1 30); do
  if docker exec $L-r1 vtysh -c "show ipv6 route isis" 2>/dev/null | grep -q '3fff:0:ff::3' &&
     docker exec $L-r1 vtysh -c "show ipv6 route isis" 2>/dev/null | grep -q '3fff:0:3::/64'; then
    echo "Convergido tras $((i*2)) s"; break
  fi
  sleep 2
done

check "r1: adyacencia IS-IS con r2 (Up)"           "docker exec $L-r1 vtysh -c 'show isis neighbor' | grep -q r2"
check "r1: adyacencia IS-IS con r3 (Up)"           "docker exec $L-r1 vtysh -c 'show isis neighbor' | grep -q r3"
check "r1: LSDB con los 3 routers"                 "[ \$(docker exec $L-r1 vtysh -c 'show isis database' | grep -cE 'r1\\.00-00|r2\\.00-00|r3\\.00-00') -ge 3 ]"
check "r1: loopback de r3 aprendido por IS-IS"     "docker exec $L-r1 vtysh -c 'show ipv6 route isis' | grep -q '3fff:0:ff::3/128'"
check "r1: red de h3 aprendida por IS-IS"          "docker exec $L-r1 vtysh -c 'show ipv6 route isis' | grep -q '3fff:0:3::/64'"
check "r1→r3 por el enlace directo (eth3)"         "docker exec $L-r1 vtysh -c 'show ipv6 route 3fff:0:ff::3/128' | grep -q 'eth3'"
check "h1 → h3 (extremo a extremo)"                "docker exec $L-h1 ping -c2 -W2 3fff:0:3::30"
check "h1 → h2"                                     "docker exec $L-h1 ping -c2 -W2 3fff:0:2::20"
check "h3 → h1 (vuelta)"                            "docker exec $L-h3 ping -c2 -W2 3fff:0:1::10"
check "rutas IS-IS marcadas proto isis en kernel"  "docker exec $L-r1 ip -6 route show proto isis | grep -q 3fff:0:ff::3"

# Reconvergencia: al caer el enlace r1-r3, la red debe recalcular sola (ida y vuelta)
echo "Probando la reconvergencia (corta el enlace r1-r3 y comprueba que h1->h3 sigue)..."
recon() {
  docker exec $L-r1 vtysh -c "conf t" -c "interface eth3" -c "shutdown" >/dev/null 2>&1
  sleep 4
  local r=1
  docker exec $L-h1 ping -c2 -W2 3fff:0:3::30 >/dev/null 2>&1 &&     docker exec $L-h3 ping -c2 -W2 3fff:0:1::10 >/dev/null 2>&1 && r=0
  docker exec $L-r1 vtysh -c "conf t" -c "interface eth3" -c "no shutdown" >/dev/null 2>&1
  sleep 4
  return $r
}
check "reconverge al caer r1-r3 (h1<->h3 por r2)"  "recon"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  docker exec $L-r1 vtysh -c "show isis neighbor"
  docker exec $L-r1 vtysh -c "show ipv6 route isis"
fi
