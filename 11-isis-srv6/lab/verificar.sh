#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 11 (plano de control SRv6 con IS-IS). Uso: ./verificar.sh
L=clab-m11
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS, SRv6 y a que FRR instale los SIDs (máx. 90 s)..."
for i in $(seq 1 45); do
  docker exec $L-r1 ip -6 route show 2>/dev/null | grep -q 'seg6local' &&
  docker exec $L-r1 ip -6 route show 5f00:0:3::/48 2>/dev/null | grep -q . && break
  sleep 2
done

# --- Plano de control: FRR configura y anuncia ---
check "r1 tiene el locator MAIN configurado"          "docker exec $L-r1 vtysh -c 'show segment-routing srv6 locator' | grep -qi '5f00:0:1::/48'"
check "r1 aprende el locator de r3 por IS-IS"          "docker exec $L-r1 ip -6 route show 5f00:0:3::/48 | grep -qiE 'proto (isis|187|15)|via '"
check "r3 aprende el locator de r1 por IS-IS"          "docker exec $L-r3 ip -6 route show 5f00:0:1::/48 | grep -qiE 'proto (isis|187|15)|via '"

# --- Plano de datos: SIDs instalados por FRR (no a mano), sobre sr0 ---
check "FRR instaló el SID End del locator en sr0 (r1)" "docker exec $L-r1 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"
check "FRR instaló SIDs End.X de adyacencia en r2"     "docker exec $L-r2 ip -6 route show | grep -qi 'End.X'"
check "El locator NO está como anycast en lo (r3)"     "! docker exec $L-r3 ip -6 route show table local 2>/dev/null | grep -q 'anycast 5f00:0:3::'"

# --- Transporte IPv6 (IGP) ---
check "r1 → loopback de r3 (3fff:0:ff::3)"             "docker exec $L-r1 ping -c2 -W2 3fff:0:ff::3"
check "h1 → h2 por IPv6 (transporte IGP)"              "docker exec $L-h1 ping -c2 -W2 3fff:0:2::20"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r1: locator SRv6 ---"      ; docker exec $L-r1 vtysh -c "show segment-routing srv6 locator" 2>&1 | head -8
  echo "--- r1: seg6local en kernel ---"; docker exec $L-r1 ip -6 route show | grep seg6local | head
  echo "--- r1: sr0 existe? ---"        ; docker exec $L-r1 ip link show sr0 2>&1 | head -2
  echo "--- r1: nodos SRv6 por IS-IS ---"; docker exec $L-r1 vtysh -c "show isis segment-routing srv6 node" 2>&1 | head -15
fi
