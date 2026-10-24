#!/usr/bin/env bash
# Comprueba la topología base del anexo de escenarios. Uso: ./verificar.sh
L=clab-esc-base
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a que IS-IS converja y FRR instale los SIDs (máx. 90 s)..."
for i in $(seq 1 45); do
  docker exec $L-r1 ip -6 route show 5f00:0:6::/48 2>/dev/null | grep -q via &&
  docker exec $L-r6 ip -6 route show 5f00:0:1::/48 2>/dev/null | grep -q via && break
  sleep 2
done

# --- Adyacencias IS-IS (una por enlace de núcleo) ---
check "r1 tiene 2 adyacencias IS-IS Up" "[ \$(docker exec $L-r1 vtysh -c 'show isis neighbor' | grep -c Up) -eq 2 ]"
check "r2 tiene 4 adyacencias IS-IS Up" "[ \$(docker exec $L-r2 vtysh -c 'show isis neighbor' | grep -c Up) -eq 4 ]"
check "r3 tiene 4 adyacencias IS-IS Up" "[ \$(docker exec $L-r3 vtysh -c 'show isis neighbor' | grep -c Up) -eq 4 ]"
check "r4 tiene 4 adyacencias IS-IS Up" "[ \$(docker exec $L-r4 vtysh -c 'show isis neighbor' | grep -c Up) -eq 4 ]"
check "r5 tiene 4 adyacencias IS-IS Up" "[ \$(docker exec $L-r5 vtysh -c 'show isis neighbor' | grep -c Up) -eq 4 ]"
check "r6 tiene 2 adyacencias IS-IS Up" "[ \$(docker exec $L-r6 vtysh -c 'show isis neighbor' | grep -c Up) -eq 2 ]"

# --- SRv6: locators y SIDs ---
check "r1: SID End del locator 5f00:0:1::/48 en sr0" "docker exec $L-r1 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "r2: SID End del locator 5f00:0:2::/48 en sr0" "docker exec $L-r2 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "r3: SID End del locator 5f00:0:3::/48 en sr0" "docker exec $L-r3 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "r4: SID End del locator 5f00:0:4::/48 en sr0" "docker exec $L-r4 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "r5: SID End del locator 5f00:0:5::/48 en sr0" "docker exec $L-r5 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "r6: SID End del locator 5f00:0:6::/48 en sr0" "docker exec $L-r6 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "r2 instaló un End.X por cada adyacencia (4)" "[ \$(docker exec $L-r2 ip -6 route show | grep -ci 'action End.X') -ge 4 ]"
check "r1 aprende el locator de r2 (5f00:0:2::/48)" "docker exec $L-r1 ip -6 route show 5f00:0:2::/48 | grep -q via"
check "r1 aprende el locator de r3 (5f00:0:3::/48)" "docker exec $L-r1 ip -6 route show 5f00:0:3::/48 | grep -q via"
check "r1 aprende el locator de r4 (5f00:0:4::/48)" "docker exec $L-r1 ip -6 route show 5f00:0:4::/48 | grep -q via"
check "r1 aprende el locator de r5 (5f00:0:5::/48)" "docker exec $L-r1 ip -6 route show 5f00:0:5::/48 | grep -q via"
check "r1 aprende el locator de r6 (5f00:0:6::/48)" "docker exec $L-r1 ip -6 route show 5f00:0:6::/48 | grep -q via"

# --- Camino más corto r1 → r6: r1-r2-r4-r6 (coste 30) ---
check "r1 sale hacia r6 por r2 (eth1)" "docker exec $L-r1 ip -6 route show 3fff:0:ff::6/128 | grep -q 'dev eth1'"
check "r2 sigue hacia r6 por r4 (eth3)" "docker exec $L-r2 ip -6 route show 3fff:0:ff::6/128 | grep -q 'dev eth3'"
check "r4 entrega en r6 (eth3)"         "docker exec $L-r4 ip -6 route show 3fff:0:ff::6/128 | grep -q 'dev eth3'"
check "coste IS-IS r1→loopback de r6 = 40 (30 + 10 de la interfaz pasiva)" "docker exec $L-r1 vtysh -c 'show isis route' | grep '3fff:0:ff::6/128' | grep -qw 40"
check "r1 → loopback de r6"             "docker exec $L-r1 ping -c2 -W2 3fff:0:ff::6"
check "r6 → loopback de r1"             "docker exec $L-r6 ping -c2 -W2 3fff:0:ff::1"

# --- Sedes cableadas (los servicios los configura cada escenario) ---
check "sw1: bridge de la VLAN 100 activo" "docker exec $L-sw1 ip link show br0 | grep -q 'state UP'"
check "sw2: bridge de la VLAN 100 activo" "docker exec $L-sw2 ip link show br0 | grep -q 'state UP'"
check "h1 tiene su dirección de la sede BLUE-1" "docker exec $L-h1 ip addr show eth1 | grep -q 192.168.10.12/24"
check "h2 tiene su dirección de la sede BLUE-2" "docker exec $L-h2 ip addr show eth1 | grep -q 192.168.20.12/24"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  for r in r1 r2 r3 r4 r5 r6; do echo "--- $r: vecinos IS-IS ---"; docker exec $L-$r vtysh -c "show isis neighbor" 2>&1 | tail -n +2; done
  echo "--- r1: rutas IS-IS ---"; docker exec $L-r1 vtysh -c "show isis route" 2>&1 | head -30
  echo "--- r1: SIDs en sr0 ---"; docker exec $L-r1 ip -6 route show dev sr0
fi
