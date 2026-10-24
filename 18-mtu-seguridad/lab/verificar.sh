#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 18 (MTU, seguridad y filtrado). Uso: ./verificar.sh
L=clab-m18
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS, SRv6 y al servicio (máx. 90 s)..."
for i in $(seq 1 45); do
  docker exec $L-r3 ip -6 route show 5f00:0:3:dc04::/128 2>/dev/null | grep -qi 'End.DX4' &&
  docker exec $L-h1 ping -c1 -W2 10.0.2.20 >/dev/null 2>&1 && break
  sleep 2
done

# --- Base ---
check "h1 → h2 IPv4 sobre SRv6 (servicio legítimo)"      "docker exec $L-h1 ping -c2 -W2 10.0.2.20"

# --- MTU: la sobrecarga de SRv6 ---
check "el núcleo tiene MTU 1500 (r1 eth2)"               "docker exec $L-r1 ip link show eth2 | grep -q 'mtu 1500'"
check "ping pequeño (-M do -s 1400) funciona"            "docker exec $L-h1 ping -c2 -W2 -M do -s 1400 10.0.2.20"
check "ping grande (-M do -s 1440) FALLA por la MTU+overhead" "! docker exec $L-h1 ping -c2 -W2 -M do -s 1440 10.0.2.20"
# El arreglo: subir la MTU del núcleo a 9000 (los dos extremos de cada enlace) y reintentar
mtu_fix() {
  for nif in r1:eth2 r2:eth1 r2:eth2 r3:eth1; do docker exec $L-${nif%:*} ip link set ${nif#*:} mtu 9000; done
  sleep 1
  docker exec $L-h1 ping -c2 -W2 -M do -s 1440 10.0.2.20 >/dev/null 2>&1; rc=$?
  for nif in r1:eth2 r2:eth1 r2:eth2 r3:eth1; do docker exec $L-${nif%:*} ip link set ${nif#*:} mtu 1500; done
  return $rc
}
check "al subir la MTU del núcleo a 9000, el ping grande con DF pasa" "mtu_fix"

# --- Seguridad: filtrado en el borde ---
check "el borde BLOQUEA inyección de SIDs internos (h1→5f00::/16)" "! docker exec $L-h1 ping -c2 -W2 5f00:0:3::"
check "la regla de filtrado existe en el PE (r1)"        "docker exec $L-r1 ip -6 rule show | grep -q '5f00::/16'"
check "el filtrado NO afecta al servicio legítimo"       "docker exec $L-h1 ping -c2 -W2 10.0.2.20"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r1: MTU de interfaces ---"      ; docker exec $L-r1 ip -br link show | grep -E 'eth|sr0'
  echo "--- r1: reglas ip -6 ---"           ; docker exec $L-r1 ip -6 rule show
  echo "--- ping grande con DF ---"         ; docker exec $L-h1 ping -c2 -W2 -M do -s 1440 10.0.2.20 2>&1 | tail -3
  echo "--- h1 -> SID interno ---"          ; docker exec $L-h1 ping -c1 -W2 5f00:0:3:: 2>&1 | tail -3
fi
