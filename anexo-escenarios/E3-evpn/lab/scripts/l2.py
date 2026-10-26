#!/usr/bin/env python3
"""Hace de PE de entrada de un VPWS sobre SRv6: mete una trama Ethernet en SRv6 (H.Encaps.L2).

FRR no implementa EVPN sobre SRv6, y el kernel de Linux solo encapsula tramas en SRv6 cuando
el paquete se enruta (modo l2encap), así que este script fabrica a mano lo que haría el PE de
entrada: una cabecera IPv6 hacia el SID End.DX2 del PE remoto, una SRH de un segmento con
Next Header 143 (Ethernet) y, dentro, la trama de la sede tal cual.

Se ejecuta en el espacio de red de un PE (r1 o r6), desde tu máquina:

  docker run --rm --net container:clab-esc-e3-r1 -v "$PWD/scripts:/lab:ro" \\
      nicolaka/netshoot:v0.13 python3 /lab/l2.py <comando> [args]

Comandos:
  arp  <SID> <mac_origen> <ip_origen> <ip_destino>
        Encapsula una PETICIÓN ARP (difusión) de la sede local: "¿quién tiene ip_destino?".
  ping <SID> <mac_origen> <ip_origen> <mac_destino> <ip_destino>
        Encapsula un ICMP Echo Request de la sede local hacia un equipo de la sede remota.
  mostrar <SID> <mac_origen> <ip_origen> <ip_destino>
        Construye el paquete de "arp", lo muestra capa a capa y calcula la sobrecarga. No envía.
"""
import sys

import socket
import time

from scapy.all import ARP, ICMP, IP, IPv6, IPv6ExtHdrSegmentRouting, Ether, conf, raw

conf.verb = 0
IPPROTO_ETHERNET = 143   # Next Header de una trama Ethernet (RFC 8986, End.DX2)


def srv6_l2(sid, trama):
    """Paquete SRv6 hacia el SID End.DX2 remoto, con la trama de la sede dentro."""
    srh = IPv6ExtHdrSegmentRouting(addresses=[sid], segleft=0, lastentry=0, nh=IPPROTO_ETHERNET)
    return IPv6(dst=sid) / srh / trama


def enviar(pkt, veces=3):
    """Envía el paquete dejando que el KERNEL ponga la cabecera IPv6 y elija el camino.

    No usamos send() de scapy: scapy busca las rutas en /proc/net/ipv6_route, donde no
    aparecen las que FRR instala con "nexthop objects" (nhid). Con un socket IPv6 de tipo
    raw y protocolo 43 (Routing Header), el kernel construye la cabecera IPv6 (con su
    dirección de origen) y enruta hacia el SID con su propia tabla, como cualquier paquete.
    """
    s = socket.socket(socket.AF_INET6, socket.SOCK_RAW, socket.IPPROTO_ROUTING)
    datos = raw(pkt[IPv6ExtHdrSegmentRouting])          # SRH + trama, sin la cabecera IPv6
    for _ in range(veces):
        s.sendto(datos, (pkt[IPv6].dst, 0))
        time.sleep(0.3)
    s.close()


def trama_arp(mac, ip_origen, ip_destino):
    return Ether(src=mac, dst="ff:ff:ff:ff:ff:ff") / ARP(op=1, hwsrc=mac, psrc=ip_origen, pdst=ip_destino)


def main(a):
    if len(a) < 1 or a[0] not in ("arp", "ping", "mostrar"):
        sys.exit(__doc__)
    cmd = a[0]
    if cmd in ("arp", "mostrar") and len(a) == 5:
        pkt = srv6_l2(a[1], trama_arp(a[2], a[3], a[4]))
    elif cmd == "ping" and len(a) == 6:
        trama = Ether(src=a[2], dst=a[4]) / IP(src=a[3], dst=a[5]) / ICMP(id=0x5e2, seq=1)
        pkt = srv6_l2(a[1], trama)
    else:
        sys.exit(__doc__)

    if cmd == "mostrar":
        pkt.show2()
        interior = len(raw(pkt[Ether]))
        total = len(raw(pkt))
        print(f"\nTrama de la sede: {interior} bytes · paquete SRv6: {total} bytes · "
              f"sobrecarga: {total - interior} bytes (40 de IPv6 + {total - interior - 40} de SRH)")
        return

    enviar(pkt)
    print(f"Enviadas 3 tramas ({cmd}) dentro de SRv6 hacia {a[1]}")


if __name__ == "__main__":
    main(sys.argv[1:])
