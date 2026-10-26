#!/usr/bin/env bash
# Hace de "controlador" del escenario E4: prepara el enlace lento y fija el camino de cada rebanada.
#
#   ./rebanadas.sh retardo [ms]   añade un retardo (10 ms por defecto) en cada sentido del enlace r3-r5
#   ./rebanadas.sh sin-retardo    lo quita
#   ./rebanadas.sh activar        ORO por arriba (r2, r4) y PLATA por abajo (r3, r5), en los dos sentidos
#   ./rebanadas.sh desactivar     quita las estáticas: las dos rebanadas vuelven al camino más corto
#   ./rebanadas.sh estado         SIDs de servicio y rutas de las dos VRF en r1 y r6
#
# FRR no tiene Flex-Algo para SRv6 ni SR Policy: lo que haría la red sola, aquí lo hace este script
# con rutas estáticas con segmentos. Lee los SIDs de servicio de cada PE en su kernel, porque BGP
# los asigna al arrancar y pueden cambiar.
L=clab-esc-e4
NS="nicolaka/netshoot:v0.13"

# SID de servicio (End.DT4) de un PE para una tabla: $1 = r1|r6, $2 = 10 (ORO) | 11 (PLATA)
sid() { docker exec $L-$1 ip -6 route show | awk -v t="vrftable $2" '/End.DT4/ && index($0, t) {print $1; exit}'; }

estaticas() {   # $1 = "" (añadir) o "no " (quitar)
  local R1ORO R1PLATA R6ORO R6PLATA
  R1ORO=$(sid r1 10); R1PLATA=$(sid r1 11); R6ORO=$(sid r6 10); R6PLATA=$(sid r6 11)
  if [ -z "$R1ORO" ] || [ -z "$R1PLATA" ] || [ -z "$R6ORO" ] || [ -z "$R6PLATA" ]; then
    echo "❌ Faltan SIDs de servicio (r1: '$R1ORO' '$R1PLATA'; r6: '$R6ORO' '$R6PLATA'). ¿Está el laboratorio levantado?"; exit 1
  fi
  docker exec $L-r1 vtysh -c "configure terminal" \
    -c "vrf ORO"   -c "${1}ip route 192.168.20.0/24 3fff:0:12::2 eth1 nexthop-vrf default segments 5f00:0:4::/$R6ORO" -c "exit-vrf" \
    -c "vrf PLATA" -c "${1}ip route 192.168.120.0/24 3fff:0:13::3 eth2 nexthop-vrf default segments 5f00:0:5::/$R6PLATA" -c "exit-vrf"
  docker exec $L-r6 vtysh -c "configure terminal" \
    -c "vrf ORO"   -c "${1}ip route 192.168.10.0/24 3fff:0:46::4 eth1 nexthop-vrf default segments 5f00:0:2::/$R1ORO" -c "exit-vrf" \
    -c "vrf PLATA" -c "${1}ip route 192.168.110.0/24 3fff:0:56::5 eth2 nexthop-vrf default segments 5f00:0:3::/$R1PLATA" -c "exit-vrf"
}

netem() {   # $1 = router, $2 = interfaz, resto = argumentos de tc
  local r=$1 i=$2; shift 2
  docker run --rm --net container:$L-$r --cap-add NET_ADMIN $NS tc qdisc "$@" dev $i root ${NETEM:-} >/dev/null 2>&1
}

case "$1" in
  retardo)
    ms=${2:-10}
    for x in "r3 eth3" "r5 eth1"; do NETEM="netem delay ${ms}ms" netem $x replace; done
    echo "Enlace r3-r5: +${ms} ms en cada sentido" ;;
  sin-retardo)
    for x in "r3 eth3" "r5 eth1"; do netem $x del; done
    echo "Enlace r3-r5: sin retardo añadido" ;;
  activar)    estaticas "";    echo "Rebanadas activas: ORO por r2-r4, PLATA por r3-r5" ;;
  desactivar) estaticas "no "; echo "Rebanadas desactivadas: las dos por el camino más corto" ;;
  estado)
    for r in r1 r6; do
      echo "--- $r: SIDs de servicio ---"; docker exec $L-$r ip -6 route show | grep End.DT4
      for v in ORO PLATA; do echo "--- $r: VRF $v ---"; docker exec $L-$r ip route show vrf $v; done
    done ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
