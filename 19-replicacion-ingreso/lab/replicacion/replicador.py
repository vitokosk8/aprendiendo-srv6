#!/usr/bin/env python3
"""Replicador en el ingreso (módulo 19): lo que haría el PE de entrada de una red SRv6.

Escucha el tráfico multicast que llega de la fuente por la interfaz de la sede y, por cada
paquete de un grupo que conoce, envía UNA COPIA a cada PE de salida con receptores (las
"hojas"), encapsulada en IPv6 hacia el SID de servicio de esa hoja.

El encapsulado lo hace el kernel: un socket IPv6 "en bruto" con protocolo 4 (IPv4) pone una
cabecera IPv6 con Next Header = 4 delante del paquete IPv4. Con un solo SID, eso es
exactamente lo que hace H.Encaps.Red: IPv6 exterior hacia el SID, sin SRH.

La lista de hojas se lee de hojas.txt (una línea por hoja: nombre y SID). Si cambias el
fichero, el replicador lo nota en el siguiente paquete. En una red real, esa lista la
mantiene BGP (rutas MVPN o EVPN de tipo 3); aquí la editas tú.
"""
import os, socket, struct, sys, time

INTERFAZ = 'eth1'                                  # la interfaz de la sede de la fuente (h1)
GRUPOS = {'233.252.0.1'}                           # grupos multicast que se replican
HOJAS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hojas.txt')

_hojas, _mtime = [], None
def hojas():
    """Lee hojas.txt si ha cambiado. Líneas: 'nombre SID'; '#' empieza un comentario."""
    global _hojas, _mtime
    try:
        m = os.stat(HOJAS).st_mtime
    except FileNotFoundError:
        return []
    if m != _mtime:
        _mtime, _hojas = m, []
        for l in open(HOJAS):
            l = l.split('#')[0].split()
            if len(l) == 2: _hojas.append((l[0], l[1]))
        print(time.strftime('%H:%M:%S'), 'hojas:', ' '.join(f'{n}={s}' for n, s in _hojas), flush=True)
    return _hojas

def suma(cabecera):
    """Checksum de la cabecera IPv4 (hay que rehacerlo al cambiar el TTL)."""
    s = sum(struct.unpack(f'!{len(cabecera) // 2}H', cabecera))
    s = (s >> 16) + (s & 0xffff); s += s >> 16
    return ~s & 0xffff

def main():
    while not os.path.exists(f'/sys/class/net/{INTERFAZ}'):       # containerlab crea eth1 tras arrancar
        time.sleep(1)
    rx = socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(0x0800))   # IPv4, sin Ethernet
    rx.bind((INTERFAZ, 0))
    tx = socket.socket(socket.AF_INET6, socket.SOCK_RAW, socket.IPPROTO_IPIP)     # IPv6 + Next Header 4
    grupos = {socket.inet_aton(g) for g in GRUPOS}
    print(time.strftime('%H:%M:%S'), f'escuchando en {INTERFAZ} los grupos {", ".join(sorted(GRUPOS))}', flush=True)
    while True:
        pkt, (_, _, tipo, _, _) = rx.recvfrom(65535)
        if tipo == socket.PACKET_OUTGOING or len(pkt) < 20 or pkt[16:20] not in grupos:
            continue
        ihl = (pkt[0] & 0x0f) * 4
        if pkt[8] <= 1:                                             # como un router: TTL 1 no se reenvía
            continue
        cab = bytearray(pkt[:ihl]); cab[8] -= 1; cab[10:12] = b'\0\0'
        cab[10:12] = struct.pack('!H', suma(bytes(cab)))
        copia = bytes(cab) + pkt[ihl:]
        enviadas = []
        for nombre, sid in hojas():
            try:
                tx.sendto(copia, (sid, 0)); enviadas.append(nombre)
            except OSError as e:
                print(time.strftime('%H:%M:%S'), f'⚠️  {nombre} ({sid}): {e}', flush=True)
        print(time.strftime('%H:%M:%S'), f'{socket.inet_ntoa(pkt[12:16])} → {socket.inet_ntoa(pkt[16:20])}:',
              f'{len(enviadas)} {"copia" if len(enviadas) == 1 else "copias"} ({" ".join(enviadas) or "ninguna hoja"})', flush=True)

if __name__ == '__main__':
    main()
