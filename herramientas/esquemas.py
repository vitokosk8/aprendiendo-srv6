#!/usr/bin/env python3
"""Genera las figuras del curso (cabeceras, paquetes y direcciones) como SVG.

Cada figura se dibuja con tres tipos de bloque, todos con la misma paleta que los esquemas
de topología (topologia.py) y los diagramas Mermaid:

  * campos()     el formato de una cabecera, fila a fila (32 bits por fila), como en los RFC
  * cadena()     cabeceras o capas una detrás de otra, con flechas de "Next Header"
  * direccion()  una dirección (o un NET de IS-IS) partida en sus trozos, con llaves

Uso, desde la raíz del repositorio:
  python3 herramientas/esquemas.py            regenera todas las figuras
  python3 herramientas/esquemas.py --lista    lista las figuras y dónde se usan

Las figuras se guardan en la carpeta img/ de su módulo o escenario. Para cambiar una,
edita su definición al final de este fichero y vuelve a ejecutarlo.
"""
import os, sys
from xml.sax.saxutils import escape

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

# Paleta: la de GitHub, la misma que los esquemas de topología.
C = {
    'azul':    ('#ddf4ff', '#0969da'),   # IPv6, direcciones, localizador
    'verde':   ('#dafbe1', '#1a7f37'),   # carga útil, paquete original, capa superior
    'naranja': ('#fff1e5', '#bc4c00'),   # SRv6: SRH, SIDs, función
    'morado':  ('#fbefff', '#8250df'),   # Ethernet, ICMPv6, campos destacados
    'amarillo':('#fff8c5', '#9a6700'),   # el campo que se explica (Next Header, uSID activo)
    'gris':    ('#f6f8fa', '#57606a'),   # relleno, opcional, argumentos
}
TXT, TXT2 = '#1f2328', '#59636e'
FUENTE = "font-family='-apple-system,Segoe UI,Helvetica,Arial,sans-serif'"
MONO = "font-family='SFMono-Regular,Menlo,Consolas,monospace'"


class Svg:
    def __init__(self):
        self.e, self.w, self.h = [], 0, 0

    def rect(self, x, y, w, h, color, dash=False, r=6):
        f, s = C[color]
        d = " stroke-dasharray='6 4'" if dash else ''
        self.e.append(f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='{r}' fill='{f}' stroke='{s}' stroke-width='1.6'{d}/>")
        self.w, self.h = max(self.w, x + w), max(self.h, y + h)

    def text(self, x, y, s, size=13, bold=False, mono=False, color=TXT, anchor='middle'):
        b = " font-weight='600'" if bold else ''
        self.e.append(f"<text x='{x}' y='{y}' font-size='{size}' {MONO if mono else FUENTE}{b} fill='{color}' "
                      f"text-anchor='{anchor}' dominant-baseline='middle'>{escape(s)}</text>")

    def lines(self, x, y, items, gap=17):
        """Varias líneas centradas en (x, y). items: [(texto, opciones)]"""
        y0 = y - gap * (len(items) - 1) / 2
        for i, (s, o) in enumerate(items):
            self.text(x, y0 + i * gap, s, **o)

    def arrow(self, x1, y1, x2, y2, color='#57606a'):
        self.e.append(f"<line x1='{x1}' y1='{y1}' x2='{x2}' y2='{y2}' stroke='{color}' stroke-width='1.8' marker-end='url(#flecha)'/>")

    def brace(self, x1, x2, y, label, sub=None, up=True, color='#57606a'):
        """Llave horizontal de x1 a x2; up=True la dibuja encima (punta hacia arriba)."""
        k = -1 if up else 1
        m, h = (x1 + x2) / 2, 9
        self.e.append(f"<path d='M{x1},{y} q0,{k*h} {h},{k*h} L{m-h},{y+k*h} q{h},0 {h},{k*h} q0,{-k*h} {h},{-k*h} "
                      f"L{x2-h},{y+k*h} q{h},0 {h},{-k*h}' fill='none' stroke='{color}' stroke-width='1.5'/>")
        ty = y + k * (2 * h + 12)
        if up and sub:                       # encima: la etiqueta arriba y el detalle pegado a la llave
            self.text(m, ty - 17, label, size=13, bold=True, color=color)
            self.text(m, ty, sub, size=12, color=TXT2)
        else:
            self.text(m, ty, label, size=13, bold=True, color=color)
            if sub:
                self.text(m, ty + 17, sub, size=12, color=TXT2)
        self.h = max(self.h, ty + 25)

    def guardar(self, ruta, titulo, nota=None, margen=24):
        top = 46
        body = '\n'.join(self.e)
        W = self.w + margen
        H = self.h + (44 if nota else 20)
        notatxt = (f"<text x='{margen}' y='{H-18}' font-size='12' {FUENTE} fill='{TXT2}'>{escape(nota)}</text>" if nota else '')
        svg = f"""<svg xmlns='http://www.w3.org/2000/svg' width='{W}' height='{H + top}' viewBox='0 {-top} {W} {H + top}'>
<defs><marker id='flecha' markerWidth='10' markerHeight='8' refX='9' refY='4' orient='auto'><path d='M0,0 L10,4 L0,8 z' fill='#57606a'/></marker></defs>
<rect x='0' y='{-top}' width='{W}' height='{H + top}' rx='10' fill='#ffffff' stroke='#d0d7de'/>
<text x='{margen}' y='{-top + 28}' font-size='15' font-weight='600' {FUENTE} fill='{TXT}'>{escape(titulo)}</text>
{body}
{notatxt}
</svg>
"""
        os.makedirs(os.path.dirname(ruta), exist_ok=True)
        open(ruta, 'w').write(svg)


# ------------------------------------------------------------------------------------------
# Los tres tipos de bloque
# ------------------------------------------------------------------------------------------
def campos(filas, bit=24, x0=24, y0=40, alto=46, notas=None):
    """filas: lista de filas; cada fila, lista de (nombre, bits, color[, detalle]).
    Una fila con un solo campo de 'alto' > 1 se escribe como (nombre, 32, color, detalle, filas_de_alto)."""
    s = Svg()
    for b in range(32):                                             # regla de bits
        s.text(x0 + b * bit + bit / 2, y0 - 12, str(b % 10), size=10, mono=True, color=TXT2)
    for b in (0, 8, 16, 24):
        s.text(x0 + b * bit + 2, y0 - 30, str(b // 8 * 8), size=10, mono=True, color=TXT2, anchor='start')
    y = y0
    for fila in filas:
        x = x0
        h = alto * (fila[0][4] if len(fila[0]) > 4 else 1)
        for c in fila:
            nombre, bits, color = c[0], c[1], c[2]
            det = c[3] if len(c) > 3 else None
            w = bits * bit
            s.rect(x, y, w, h, color, dash=(color == 'gris' and nombre.startswith('…')), r=3)
            items = [(nombre, {'bold': True, 'size': 13 if w > 90 else 11})]
            if det: items.append((det, {'size': 11, 'color': TXT2}))
            s.lines(x + w / 2, y + h / 2, items, gap=16)
            x += w
        y += h
    s.text(x0 + 32 * bit + 10, y0 + 8, '', anchor='start')
    if notas:
        for (fila_y, texto) in notas:                                # anotaciones a la derecha
            s.text(x0 + 32 * bit + 14, y0 + fila_y, texto, size=12, color=TXT2, anchor='start')
            s.w = max(s.w, x0 + 32 * bit + 14 + 7.2 * len(texto))
    return s


def cadena(cajas, ancho=170, alto=96, sep=46, x0=24, y0=6, llaves=()):
    """cajas: (título, [líneas], color). Flechas entre cajas. llaves: (desde, hasta, texto, sub)."""
    s = Svg()
    xs = []
    for i, (titulo, lineas, color) in enumerate(cajas):
        w = ancho if not isinstance(color, tuple) else color[1]
        col = color if not isinstance(color, tuple) else color[0]
        x = x0 + sum((c[2][1] if isinstance(c[2], tuple) else ancho) + sep for c in cajas[:i])
        xs.append((x, x + w))
        s.rect(x, y0, w, alto, col)
        items = [(titulo, {'bold': True, 'size': 14})] + [(l, {'size': 12, 'mono': '=' in l or ':' in l, 'color': TXT2 if '=' not in l else TXT}) for l in lineas]
        s.lines(x + w / 2, y0 + alto / 2, items, gap=18)
        if i and sep > 12:                   # cajas separadas: flecha; contiguas (un paquete): sin flecha
            s.arrow(xs[i - 1][1] + 4, y0 + alto / 2, x - 4, y0 + alto / 2)
    for (a, b, texto, sub) in llaves:
        s.brace(xs[a][0] + 2, xs[b][1] - 2, y0 + alto + 10, texto, sub, up=False)
    return s


def direccion(trozos, x0=24, y0=60, alto=48, llaves_arriba=(), llaves_abajo=(), resultado=None):
    """trozos: (texto, ancho_px, color, etiqueta_debajo). Llaves: (desde, hasta, texto, sub)."""
    s = Svg()
    xs, x = [], x0
    for (txt, w, color, etiqueta) in trozos:
        s.rect(x, y0, w, alto, color, r=4)
        s.text(x + w / 2, y0 + alto / 2, txt, size=16, mono=True, bold=True)
        xs.append((x, x + w))
        x += w + 4
    for (a, b, texto, sub) in llaves_arriba:
        s.brace(xs[a][0] + 2, xs[b][1] - 2, y0 - 8, texto, sub, up=True)
    for (a, b, texto, sub) in llaves_abajo:
        s.brace(xs[a][0] + 2, xs[b][1] - 2, y0 + alto + 8, texto, sub, up=False)
    if resultado:
        s.text(x0, s.h + 18, resultado, size=14, mono=True, bold=True, anchor='start')
        s.h += 30
    return s


# ------------------------------------------------------------------------------------------
# Las figuras del curso. (ruta, título, función que dibuja, nota al pie)
# ------------------------------------------------------------------------------------------
def capas():
    return cadena([
        ('Ethernet', ['14 bytes', 'EtherType = 0x86DD'], 'morado'),
        ('IPv6', ['40 bytes', 'Next Header = 58'], 'azul'),
        ('ICMPv6', ['8 bytes', 'Type = 128 (Echo Request)'], ('verde', 200)),
        ('datos', ['lo que envía ping'], 'gris'),
    ], ancho=170, sep=4, llaves=[(1, 3, 'lo que viaja dentro de la trama Ethernet', 'cada cabecera dice qué viene detrás')])

def cabecera_ipv6():
    return campos([
        [('Version', 4, 'azul', '= 6'), ('Traffic Class', 8, 'azul', 'DSCP + ECN'), ('Flow Label', 20, 'azul', 'marca el flujo')],
        [('Payload Length', 16, 'azul', 'bytes detrás de esta cabecera'), ('Next Header', 8, 'amarillo', 'qué viene detrás'), ('Hop Limit', 8, 'azul', 'el TTL')],
        [('Source Address', 32, 'verde', '128 bits: quién envía', 2)],
        [('Destination Address', 32, 'naranja', '128 bits: a quién va (en SRv6, el SID activo)', 2)],
    ], notas=[(23, '4 bytes por fila'), (69, '8 bytes de campos de control'), (138, '+ 16 bytes'), (230, '+ 16 bytes = 40 bytes')])

def cabecera_icmpv6():
    return campos([
        [('Type', 8, 'morado', 'qué mensaje'), ('Code', 8, 'morado', 'la variante'), ('Checksum', 16, 'gris')],
        [('Cuerpo del mensaje', 32, 'verde', 'depende del Type (longitud variable)')],
    ], notas=[(23, '0–127: errores · 128–255: informativos')])

def cadena_extension():
    return cadena([
        ('IPv6', ['Next Header = 0'], 'azul'),
        ('Hop-by-Hop', ['Next Header = 43'], 'morado'),
        ('Routing', ['Next Header = 6'], 'naranja'),
        ('TCP', ['la capa superior'], 'verde'),
    ], alto=78)

def paquete_srv6():
    return cadena([
        ('IPv6 exterior', ['Next Header = 43', 'dst = SID activo'], 'azul'),
        ('SRH', ['Routing Header tipo 4', 'Next Header = 41', 'lista de SIDs'], ('naranja', 190)),
        ('IPv6 interior', ['Next Header = 58', 'el paquete original'], 'verde'),
        ('ICMPv6', ['echo'], ('verde', 120)),
    ], alto=104, llaves=[(0, 1, 'lo que añade SRv6', 'el encapsulado'), (2, 3, 'el paquete original', 'intacto')])

def cabecera_srh():
    return campos([
        [('Next Header', 8, 'azul'), ('Hdr Ext Len', 8, 'gris'), ('Routing Type', 8, 'naranja', '= 4 (SRH)'), ('Segments Left', 8, 'amarillo', 'cuál es el activo')],
        [('Last Entry', 8, 'gris', 'índice del último'), ('Flags', 8, 'gris'), ('Tag', 16, 'gris')],
        [('Segment List [0]', 32, 'naranja', '128 bits · el ÚLTIMO SID del camino', 1.4)],
        [('…', 32, 'gris', '', 0.6)],
        [('Segment List [n]', 32, 'naranja', '128 bits · el PRIMERO del camino', 1.4)],
        [('TLVs opcionales', 32, 'gris', 'HMAC, relleno…')],
    ], notas=[(23, '8 bytes fijos'), (69, ''), (124, 'la lista va AL REVÉS:'), (142, 'el primer segmento, al final'), (218, '16 bytes por SID')])

def sid():
    return direccion([
        ('5f00:0000', 190, 'azul', ''), ('0002', 90, 'azul', ''), ('e000', 90, 'naranja', ''), ('0000:0000:0000:0000', 260, 'gris', ''),
    ], llaves_arriba=[(0, 1, 'localizador', '"a dónde ir": prefijo enrutable'), (2, 2, 'función', '"qué hacer"'), (3, 3, 'argumentos', '"datos opcionales"')],
       llaves_abajo=[(0, 0, 'bloque', '32 bits'), (1, 1, 'nodo', '16 bits'), (2, 2, 'func', '16 bits'), (3, 3, '64 bits', 'casi siempre 0')],
       y0=92, resultado='= 5f00:0:2:e000::  (End de r2)')

def sobrecarga():
    return cadena([
        ('IPv6 exterior', ['40 bytes'], 'azul'),
        ('SRH', ['8 + 16·N bytes', 'N = nº de SIDs'], ('naranja', 180)),
        ('paquete original', ['IPv4 o IPv6, intacto'], ('verde', 240)),
    ], alto=84, sep=4, llaves=[(0, 1, 'sobrecarga SRv6 = 48 + 16·N bytes', 'con H.Encaps.Red y un solo SID: 40 bytes, sin SRH')])

def contenedor_usid():
    return direccion([
        ('5f00:0000', 190, 'azul', ''), ('0002', 90, 'amarillo', ''), ('0003', 80, 'naranja', ''), ('0000', 80, 'gris', ''),
        ('0000', 80, 'gris', ''), ('0000', 80, 'gris', ''), ('0000', 80, 'gris', ''),
    ], llaves_arriba=[(0, 0, 'bloque', '32 bits'), (1, 1, 'uSID activo', 'el de r2'), (2, 6, 'resto de uSID: el "argumento"', 'se desplazan 16 bits en cada uN')],
       y0=92, resultado='= 5f00:0:2:3::   (r2, después r3)')

def contenedor_te():
    return direccion([
        ('5f00:0000', 190, 'azul', ''), ('0005', 90, 'amarillo', ''), ('0006', 90, 'naranja', ''), ('XXXX', 90, 'naranja', ''),
        ('0000', 80, 'gris', ''), ('0000', 80, 'gris', ''), ('0000', 80, 'gris', ''),
    ], llaves_arriba=[(0, 0, 'bloque', '32 bits'), (1, 1, 'uN de r5', 'activo'), (2, 2, 'uN de r6', ''), (3, 3, 'función de r6', 'uDT46'), (4, 6, 'fin del contenedor', '')],
       y0=92, resultado='= 5f00:0:5:6:XXXX::   (por r5, hasta el SID de servicio de r6)')

def net_isis():
    return direccion([('49', 70, 'morado', ''), ('0001', 100, 'azul', ''), ('0000.0000.0001', 230, 'naranja', ''), ('00', 70, 'gris', '')],
        llaves_abajo=[(0, 0, 'AFI', '49 = privado'), (1, 1, 'Área', '0001'), (2, 2, 'System ID', '6 bytes, único por router'), (3, 3, 'NSEL', '00 en un router')],
        y0=20, resultado='NET = 49.0001.0000.0000.0001.00')


def cabecera_bier():
    return campos([
        [('BIFT-id', 20, 'naranja', 'qué BIFT usar (dominio, BSL, SI)'), ('TC', 3, 'gris'), ('S', 1, 'gris'), ('TTL', 8, 'azul', 'saltos BIER')],
        [('Nibble', 4, 'gris', '0101'), ('Ver', 4, 'gris'), ('BSL', 4, 'naranja', 'longitud'), ('Entropy', 20, 'gris', 'para el reparto (ECMP)')],
        [('OAM', 2, 'gris'), ('Rsv', 2, 'gris'), ('DSCP', 6, 'gris'), ('Proto', 6, 'morado', 'qué va dentro'), ('BFIR-id', 16, 'azul', 'quién lo metió en BIER')],
        [('BitString', 32, 'amarillo', 'un bit por BFER: 64 a 4096 bits (en el laboratorio, 64)', 2)],
    ], notas=[(23, '12 bytes fijos'), (176, 'el bit k (desde la derecha)'), (194, 'es el BFER con BFR-id k')])


FIGURAS = [
    ('02-cabecera-ipv6/img/paquete-capas.svg', 'Un ping de h1 a h2: cabeceras dentro de cabeceras', capas, None),
    ('02-cabecera-ipv6/img/cabecera-ipv6.svg', 'La cabecera IPv6 (RFC 8200)', cabecera_ipv6, 'Siempre 40 bytes. Cada fila son 32 bits.'),
    ('02-cabecera-ipv6/img/cadena-extension.svg', 'Cabeceras de extensión: una cadena de Next Header', cadena_extension, 'Cada cabecera dice cuál viene detrás. 0 = Hop-by-Hop, 43 = Routing, 6 = TCP.'),
    ('02-cabecera-ipv6/img/paquete-srv6.svg', 'Así se ve un paquete SRv6 (encapsulado)', paquete_srv6, None),
    ('03-icmpv6-nd/img/cabecera-icmpv6.svg', 'El principio de todo mensaje ICMPv6', cabecera_icmpv6, 'Va detrás de la cabecera IPv6, con Next Header = 58.'),
    ('05-isis/img/net-isis.svg', 'La dirección de un router IS-IS: el NET', net_isis, None),
    ('07-sid-srh/img/estructura-sid.svg', 'Las partes de un SID (RFC 8986)', sid, None),
    ('07-sid-srh/img/cabecera-srh.svg', 'La Segment Routing Header (RFC 8754)', cabecera_srh, 'Es una cabecera de extensión de tipo Routing (Next Header = 43 en la cabecera anterior).'),
    ('09-reduccion-cabeceras/img/sobrecarga-srv6.svg', 'Lo que SRv6 añade a cada paquete', sobrecarga, None),
    ('10-usid/img/contenedor-usid.svg', 'Un contenedor uSID (formato F3216)', contenedor_usid, 'Caben 6 uSID de 16 bits detrás del bloque de 32 bits.'),
    ('21-bier/img/cabecera-bier.svg', 'La cabecera BIER (RFC 8296)', cabecera_bier, 'Va detrás de la cabecera IPv6 (BIERin6) o de una etiqueta MPLS. Detrás, el paquete original.'),
    ('anexo-escenarios/E5-usid-migracion/img/contenedor-te.svg', 'E5 · El camino de TE en un solo contenedor', contenedor_te, None),
]

if __name__ == '__main__':
    if '--lista' in sys.argv:
        for ruta, titulo, _, _ in FIGURAS: print(f'{ruta:60} {titulo}')
        sys.exit(0)
    for ruta, titulo, f, nota in FIGURAS:
        f().guardar(os.path.join(RAIZ, ruta), titulo, nota)
        print('✔', ruta)
