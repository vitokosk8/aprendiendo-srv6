#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 15 (resiliencia TI-LFA). Uso: ./verificar.sh
L=clab-m15
T=$(mktemp -d)   # carpeta temporal propia de esta ejecución
trap \'rm -rf "$T"\' EXIT
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS, SRv6 y al cálculo del fast-reroute (máx. 90 s)..."
for i in $(seq 1 45); do
  docker exec $L-r1 ip -6 route show 5f00:0:4::/48 2>/dev/null | grep -q 'dev eth2' &&
  docker exec $L-r1 ip -6 route show dev sr0 2>/dev/null | grep -qi 'seg6local action End' && break
  sleep 2
done

# --- Transporte y SRv6 ---
check "FRR instaló el SID End en sr0 (r1)"             "docker exec $L-r1 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "r3 (respaldo) tiene SIDs de transporte"         "docker exec $L-r3 ip -6 route show | grep -qi 'seg6local action End'"

# --- Fast-reroute / TI-LFA ---
check "r1 tiene fast-reroute LFA configurado"          "docker exec $L-r1 vtysh -c 'show running-config' | grep -qi 'fast-reroute lfa'"
check "r1 tiene cobertura de fast-reroute (LFA 100%)"  "docker exec $L-r1 vtysh -c 'show isis fast-reroute summary' | grep -q '100.00%'"

# --- Camino primario (por r2) ---
check "El camino primario a r4 va por r2 (eth2)"       "docker exec $L-r1 ip -6 route show 3fff:0:ff::4/128 | grep -q 'dev eth2'"
check "r1 → r4 (loopback) por el primario"             "docker exec $L-r1 ping -c2 -W2 3fff:0:ff::4"

# --- Conmutación: romper el enlace primario r1-r2 ---
failover() {
  docker exec $L-r1 ip link set eth2 down
  sleep 4
  docker exec $L-r1 ping -c3 -W2 3fff:0:ff::4 >$T/m15_fo.txt 2>&1; rc=$?
  # ¿va ahora por r3 (eth3)?
  docker exec $L-r1 ip -6 route show 3fff:0:ff::4/128 >$T/m15_rt.txt 2>&1
  docker exec $L-r1 ip link set eth2 up
  return $rc
}
echo "Probando la conmutación (se rompe r1-r2 unos segundos)..."
check "tras romper r1-r2, r1 sigue alcanzando r4 (respaldo por r3)" "failover"
check "durante el fallo, la ruta a r4 pasó por r3 (eth3)"           "grep -q 'dev eth3' $T/m15_rt.txt"

sleep 12  # dar tiempo a que IS-IS reestablezca la adyacencia y vuelva el primario
check "restaurado el enlace, r1 → r4 vuelve a funcionar"            "docker exec $L-r1 ping -c3 -W2 3fff:0:ff::4"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r1: fast-reroute summary ---" ; docker exec $L-r1 vtysh -c "show isis fast-reroute summary" 2>&1 | head -15
  echo "--- r1: ruta a r4 (backup) ---"   ; docker exec $L-r1 vtysh -c "show isis route level-2 backup" 2>&1 | grep -A2 '3fff:0:ff::4' | head
  echo "--- r1: ruta kernel a r4 ---"     ; docker exec $L-r1 ip -6 route show 3fff:0:ff::4/128
  echo "--- ping durante el fallo ---"    ; cat $T/m15_fo.txt 2>/dev/null | tail -3
  echo "--- ruta durante el fallo ---"    ; cat $T/m15_rt.txt 2>/dev/null
fi
