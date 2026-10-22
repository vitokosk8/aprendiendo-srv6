#!/usr/bin/env python3
"""Fabrica paquetes IPv6 a medida y muestra la respuesta.

Uso (desde tu máquina):
  docker exec clab-m02-h1 python3 /lab/paquetes.py <experimento> [destino]

Experimentos:
  basico         ping normal (ICMPv6 Echo Request)
  tc             Traffic Class = 0xb8 (DSCP 46, "Expedited Forwarding")
  flow           Flow Label = 0x12345
  hoplimit N     Hop Limit = N (prueba con 1, 2 y 3)
  hbh-saltar     Hop-by-Hop con una opción desconocida que se puede saltar
  hbh-descartar  Hop-by-Hop con una opción desconocida que obliga a descartar
  dst-saltar     Destination Options con una opción que se puede saltar
  dst-descartar  Destination Options con una opción que obliga a descartar
  srh            Segment Routing Header con Segments Left = 0
  rh0            Routing Header tipo 0 (obsoleto) con Segments Left = 1
  cadena         Hop-by-Hop + Destination Options + ICMPv6, para ver la cadena

El destino por defecto es h2 (3fff:0:2::10).
"""
import sys

from scapy.all import (
    ICMPv6EchoRequest,
    IPv6,
    IPv6ExtHdrDestOpt,
    IPv6ExtHdrHopByHop,
    IPv6ExtHdrRouting,
    IPv6ExtHdrSegmentRouting,
    HBHOptUnknown,
    conf,
    sr1,
)

conf.verb = 0

# Tipo de opción (RFC 8200 §4.2). Los dos bits altos dicen qué hacer si no se reconoce:
#   00 → saltar la opción y seguir procesando
#   10 → descartar el paquete y enviar ICMPv6 Parameter Problem al origen
OPT_SALTAR = 0x1E      # 00 0 11110
OPT_DESCARTAR = 0x9E   # 10 0 11110


def opcion(tipo):
    # 4 bytes de datos: 2 (tipo + longitud) + 4 = 6, más 2 de cabecera = 8 bytes exactos
    return HBHOptUnknown(otype=tipo, optdata=b"\xca\xfe\xca\xfe")


def construir(exp, dst, arg):
    ip = IPv6(dst=dst)
    echo = ICMPv6EchoRequest(id=0x0202, seq=1, data=b"aprendiendo-srv6")
    if exp == "basico":
        return ip / echo
    if exp == "tc":
        return IPv6(dst=dst, tc=0xB8) / echo
    if exp == "flow":
        return IPv6(dst=dst, fl=0x12345) / echo
    if exp == "hoplimit":
        return IPv6(dst=dst, hlim=int(arg or 1)) / echo
    if exp == "hbh-saltar":
        return ip / IPv6ExtHdrHopByHop(options=[opcion(OPT_SALTAR)]) / echo
    if exp == "hbh-descartar":
        return ip / IPv6ExtHdrHopByHop(options=[opcion(OPT_DESCARTAR)]) / echo
    if exp == "dst-saltar":
        return ip / IPv6ExtHdrDestOpt(options=[opcion(OPT_SALTAR)]) / echo
    if exp == "dst-descartar":
        return ip / IPv6ExtHdrDestOpt(options=[opcion(OPT_DESCARTAR)]) / echo
    if exp == "srh":
        return ip / IPv6ExtHdrSegmentRouting(addresses=[dst], segleft=0) / echo
    if exp == "rh0":
        return ip / IPv6ExtHdrRouting(type=0, addresses=["3fff:0:1::10"], segleft=1) / echo
    if exp == "cadena":
        return (ip / IPv6ExtHdrHopByHop(options=[opcion(OPT_SALTAR)])
                / IPv6ExtHdrDestOpt(options=[opcion(OPT_SALTAR)]) / echo)
    sys.exit(f"Experimento desconocido: {exp}\n\n{__doc__}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    exp = sys.argv[1]
    arg = sys.argv[2] if exp == "hoplimit" and len(sys.argv) > 2 else None
    rest = sys.argv[3:] if exp == "hoplimit" else sys.argv[2:]
    dst = rest[0] if rest else "3fff:0:2::10"

    pkt = construir(exp, dst, arg)
    print("=" * 70)
    print(f"ENVIADO  ({len(bytes(pkt))} bytes)")
    print("=" * 70)
    pkt.show2()

    resp = sr1(pkt, timeout=3)
    print("=" * 70)
    if resp is None:
        print("RESPUESTA: ninguna en 3 segundos")
        return
    print(f"RESPUESTA de {resp[IPv6].src}: {resp.lastlayer().summary()}")
    print("=" * 70)
    resp.show2()


if __name__ == "__main__":
    main()
