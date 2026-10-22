#!/usr/bin/env python3
"""Fabrica y disecciona un paquete SRv6 (IPv6 + SRH).

Uso (desde tu máquina):
  docker exec clab-m07-h1 python3 /lab/srh.py <comando> [args]

Comandos:
  construir [SID1,SID2,...] [destino_interior]
        Construye un paquete SRv6 con esa lista de segmentos y un ICMPv6 Echo
        dentro, lo muestra campo a campo y calcula la sobrecarga en bytes.
        Por defecto: SIDs 5f00:0:2:e000::,5f00:0:3:e000:: y destino 3fff:0:2::20 (h2).

  enviar [SID1,SID2,...] [destino_interior]
        Lo mismo, pero además lo envía y espera la respuesta de h2.

  sid <dirección>
        Disecciona un SID en localizador / función / argumentos (formato uSID
        F3216: bloque 32 bits, nodo 16, función 16).

Recuerda: la lista de segmentos se escribe en el ORDEN DEL CAMINO
(primer salto primero). El script la coloca en la SRH en orden inverso, como
manda el RFC 8754.
"""
import sys
import time

from scapy.all import (
    ICMPv6EchoRequest,
    IPv6,
    IPv6ExtHdrSegmentRouting,
    AsyncSniffer,
    conf,
    send,
)

conf.verb = 0

SIDS_DEF = ["5f00:0:2:e000::", "5f00:0:3:e000::"]
DST_DEF = "3fff:0:2::20"
SRC = "3fff:0:1::10"


def construir(sids, dst):
    # La SRH guarda los segmentos en orden inverso: addresses[0] es el ÚLTIMO del
    # camino. Scapy invierte la lista que le pasamos, así que se la damos en orden
    # inverso para que quede como el camino que queremos.
    # Modo ENCAP (H.Encaps): cabecera IPv6 exterior + SRH + el paquete original
    # (IPv6 interior) entero dentro. La SRH apunta a los SID; el paquete interior
    # lleva el destino real. Es lo que desencapsula End.DT6.
    srh = IPv6ExtHdrSegmentRouting(addresses=sids[::-1], segleft=len(sids) - 1,
                                   lastentry=len(sids) - 1, nh=41)  # 41 = IPv6 interior
    interior = IPv6(src=SRC, dst=dst) / ICMPv6EchoRequest(id=0x0707, seq=1,
                                                          data=b"modulo-07-srh")
    return IPv6(src=SRC, dst=sids[0]) / srh / interior


def mostrar(pkt, sids, dst):
    print("=" * 72)
    print("PAQUETE SRv6 CONSTRUIDO")
    print("=" * 72)
    pkt.show2()
    n = len(sids)
    total = len(bytes(pkt))
    srh_len = 8 + 16 * n
    print("-" * 72)
    print("Lectura de los campos clave:")
    print(f"  Dirección de destino exterior = {sids[0]}  (el SID activo, el primer salto)")
    print(f"  Segments Left (SL)            = {n - 1}  (índice del SID activo)")
    print(f"  Last Entry                    = {n - 1}  (índice del último elemento)")
    print(f"  Segment List (orden inverso):")
    for i, s in enumerate(sids[::-1]):
        marca = "  <- SID activo (SL apunta aquí)" if i == n - 1 else ""
        print(f"     [{i}] {s}{marca}")
    print(f"  Destino interior              = {dst}  (el paquete original)")
    print("-" * 72)
    print("Sobrecarga en bytes (lo que se añade al paquete interior):")
    print(f"  IPv6 exterior = 40   SRH = 8 + 16*{n} = {srh_len}   total añadido = {40 + srh_len}")
    print(f"  Fórmula: 40 (IPv6 exterior) + 8 (SRH fija) + 16 x (nº de SIDs)")
    print("=" * 72)


def enviar(pkt):
    sniffer = AsyncSniffer(iface="eth1", count=1, timeout=3,
                           filter="icmp6 and ip6[40]==129")  # Echo Reply
    sniffer.start()
    time.sleep(0.5)
    send(pkt)
    sniffer.join()
    print()
    if sniffer.results:
        r = sniffer.results[0]
        print(f"RESPUESTA de {r[IPv6].src}: {r.lastlayer().summary()}")
        print("(h2 contestó: el paquete recorrió toda la lista de SIDs y se entregó)")
    else:
        print("RESPUESTA: ninguna en 3 segundos")


def diseccionar_sid(addr):
    full = IPv6(dst=addr).dst  # normaliza
    import ipaddress
    b = ipaddress.IPv6Address(addr).packed
    bloque = b[0:4].hex()
    nodo = b[4:6].hex()
    func = b[6:8].hex()
    args = b[8:16].hex()
    print(f"SID {addr}  (formato uSID F3216)")
    print(f"  Localizador (48 bits) = bloque {bloque} + nodo {nodo}  ->  prefijo enrutable")
    print(f"  Función     (16 bits) = {func}")
    print(f"  Argumentos  (64 bits) = {args}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "sid":
        diseccionar_sid(sys.argv[2] if len(sys.argv) > 2 else "5f00:0:3:e000::")
        return
    rest = sys.argv[2:]
    sids = rest[0].split(",") if rest else SIDS_DEF
    dst = rest[1] if len(rest) > 1 else DST_DEF
    pkt = construir(sids, dst)
    mostrar(pkt, sids, dst)
    if cmd == "enviar":
        enviar(pkt)
    elif cmd != "construir":
        sys.exit(f"Comando desconocido: {cmd}\n\n{__doc__}")


if __name__ == "__main__":
    main()
