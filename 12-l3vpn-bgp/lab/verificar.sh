#!/usr/bin/env bash
# Comprueba el laboratorio del módulo 12 (L3VPN IPv4 sobre SRv6 con BGP). Uso: ./verificar.sh
L=clab-m12
ok=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; ok=$((ok+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }

echo "Esperando a IS-IS, BGP y a las rutas VPN (máx. 120 s)..."
for i in $(seq 1 60); do
  docker exec $L-r1 vtysh -c "show bgp ipv4 vpn summary json" 2>/dev/null | grep -q '"state":"Established"' &&
  docker exec $L-r3 ip -6 route show 2>/dev/null | grep -qi 'End.DT4' &&
  docker exec $L-r1 ip -6 route show 2>/dev/null | grep -qi 'End.DT4' &&
  docker exec $L-r1 vtysh -c "show ip route vrf CUST 10.0.2.0/24" 2>/dev/null | grep -qi 'bgp' && break
  sleep 2
done

# --- Transporte (IS-IS + SRv6, como el módulo 11) ---
check "r1 aprende el locator de r3 por IS-IS"          "docker exec $L-r1 ip -6 route show 5f00:0:3::/48 | grep -q ."
check "FRR instaló los SIDs de transporte en sr0 (r1)" "docker exec $L-r1 ip -6 route show dev sr0 | grep -qi 'seg6local action End'"

# --- Servicio (BGP L3VPN) ---
check "Sesión iBGP VPN establecida (r1 ↔ r3)"          "docker exec $L-r1 vtysh -c 'show bgp ipv4 vpn summary json' | grep -q '\"state\":\"Established\"'"
check "r1 tiene la VRF CUST"                            "docker exec $L-r1 ip link show CUST | grep -qi 'master\|vrf'"
check "r1 instaló su SID End.DT4 por BGP (vrftable 10)" "docker exec $L-r1 ip -6 route show | grep -i 'End.DT4' | grep -q 'table 10'"
check "r3 instaló su SID End.DT4 por BGP (vrftable 10)" "docker exec $L-r3 ip -6 route show | grep -i 'End.DT4' | grep -q 'table 10'"
check "r1 aprende 10.0.2.0/24 en la VRF por BGP"        "docker exec $L-r1 vtysh -c 'show ip route vrf CUST 10.0.2.0/24' | grep -qi 'bgp\|seg6'"
check "r2 (P) NO tiene la VRF CUST"                     "! docker exec $L-r2 ip link show CUST >/dev/null 2>&1"
check "r2 (P) NO tiene ningún End.DT4"                  "! docker exec $L-r2 ip -6 route show | grep -qi 'End.DT4'"

# --- Plano de datos de cliente ---
check "h1 → h2 por la VPN (IPv4 sobre SRv6)"            "docker exec $L-h1 ping -c2 -W2 10.0.2.20"
check "h2 → h1 por la VPN (vuelta)"                     "docker exec $L-h2 ping -c2 -W2 10.0.1.10"

echo; echo "Resultado: $ok correctas, $fail fallidas"
if [ $fail -gt 0 ]; then
  echo; echo "Información para depurar:"
  echo "--- r1: BGP VPN summary ---"   ; docker exec $L-r1 vtysh -c "show bgp ipv4 vpn summary" 2>&1 | tail -6
  echo "--- r1: ruta VRF a h2 ---"     ; docker exec $L-r1 vtysh -c "show ip route vrf CUST 10.0.2.0/24" 2>&1 | head
  echo "--- r3: End.DT4 en kernel ---" ; docker exec $L-r3 ip -6 route show | grep -i 'seg6local' | head
  echo "--- r3: locator detalle ---"   ; docker exec $L-r3 vtysh -c "show segment-routing srv6 locator MAIN detail" 2>&1 | head
  echo "--- r3: strict_mode ---"       ; docker exec $L-r3 sysctl net.vrf.strict_mode 2>&1
  echo "--- h1 → h2 ---"               ; docker exec $L-h1 ping -c2 -W2 10.0.2.20 2>&1 | tail -3
fi
