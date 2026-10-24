#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 13 (L3VPN dual-stack sobre SRv6). Uso: ./verificar.sh
L=clab-m13
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS, BGP y a las rutas VPN (máx. 120 s)..."
for i in $(seq 1 60); do
  docker exec $L-r3 ip -6 route show 2>/dev/null | grep -qi 'End.DT46' &&
  docker exec $L-r1 vtysh -c "show ip route vrf CUST 10.0.2.0/24" 2>/dev/null | grep -qi 'bgp' &&
  docker exec $L-r1 vtysh -c "show ipv6 route vrf CUST 2001:db8:2::/64" 2>/dev/null | grep -qi 'bgp' && break
  sleep 2
done

# --- Transporte ---
check "FRR instaló los SIDs de transporte en sr0 (r1)"  "docker exec $L-r1 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"

# --- Servicio BGP L3VPN dual-stack ---
check "Sesión iBGP VPN establecida (r1 ↔ r3)"           "docker exec $L-r1 vtysh -c 'show bgp ipv4 vpn summary json' | grep -q '\"state\":\"Established\"'"
check "r3 instaló un SID End.DT46 por BGP (vrftable 10)" "docker exec $L-r3 ip -6 route show | grep -i 'End.DT46' | grep -q 'table 10'"
check "r1 aprende 10.0.2.0/24 (IPv4) en la VRF"          "docker exec $L-r1 vtysh -c 'show ip route vrf CUST 10.0.2.0/24' | grep -qi 'bgp\|seg6'"
check "r1 aprende 2001:db8:2::/64 (IPv6) en la VRF"      "docker exec $L-r1 vtysh -c 'show ipv6 route vrf CUST 2001:db8:2::/64' | grep -qi 'bgp\|seg6'"
check "r2 (P) NO tiene ningún SID End.DT*"               "! docker exec $L-r2 ip -6 route show | grep -qiE 'End.DT'"

# --- Plano de datos de cliente (ambas familias) ---
check "h1 → h2 IPv4 por la VPN"                          "docker exec $L-h1 ping -c2 -W2 10.0.2.20"
check "h1 → h2 IPv6 por la VPN"                          "docker exec $L-h1 ping -c2 -W2 2001:db8:2::20"
check "h2 → h1 IPv4 por la VPN (vuelta)"                 "docker exec $L-h2 ping -c2 -W2 10.0.1.10"
check "h2 → h1 IPv6 por la VPN (vuelta)"                 "docker exec $L-h2 ping -c2 -W2 2001:db8:1::10"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r1: BGP VPN summary (v4) ---" ; docker exec $L-r1 vtysh -c "show bgp ipv4 vpn summary" 2>&1 | tail -4
  echo "--- r3: SIDs seg6local ---"       ; docker exec $L-r3 ip -6 route show | grep -i 'seg6local' | head
  echo "--- r3: strict_mode ---"          ; docker exec $L-r3 sysctl net.vrf.strict_mode 2>&1
  echo "--- r1: ruta VRF v6 a h2 ---"     ; docker exec $L-r1 vtysh -c "show ipv6 route vrf CUST 2001:db8:2::/64" 2>&1 | head
  echo "--- h1 → h2 v6 ---"               ; docker exec $L-h1 ping -c2 -W2 2001:db8:2::20 2>&1 | tail -3
fi
