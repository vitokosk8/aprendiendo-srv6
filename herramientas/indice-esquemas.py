#!/usr/bin/env python3
"""Genera ESQUEMAS.md: el índice de todas las figuras, diagramas y topologías del curso.

Recorre los README, prácticas y soluciones de los módulos y del anexo, y recoge:

  * las figuras SVG (las imágenes de las carpetas img/, generadas por esquemas.py)
  * los diagramas Mermaid que no son de topología (su título es la línea "%% …" del principio)
  * los esquemas de topología de cada laboratorio (los que escribe topologia.py)

Cada entrada enlaza directamente a la sección donde está. Uso, desde la raíz del repositorio:
  python3 herramientas/indice-esquemas.py
"""
import os, re

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
TIPOS = {'sequenceDiagram': 'secuencia', 'stateDiagram-v2': 'estados', 'graph': 'grafo', 'flowchart': 'grafo'}


def ancla(titulo, vistos):
    """El ancla que GitHub genera para un encabezado."""
    t = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', titulo.strip().lower())
    t = re.sub(r'[^\w\- ]', '', t).replace(' ', '-')
    n = vistos.get(t, 0); vistos[t] = n + 1
    return t if n == 0 else f'{t}-{n}'


def carpetas():
    """Módulos y escenarios, en el orden del curso."""
    mods = sorted(d for d in os.listdir(RAIZ) if re.match(r'\d\d-', d))
    anexo = os.path.join(RAIZ, 'anexo-escenarios')
    esc = ['anexo-escenarios/topologia-base'] + sorted(
        f'anexo-escenarios/{d}' for d in os.listdir(anexo) if re.match(r'E\d+-', d))
    return mods + esc


def recorrer(carpeta):
    figuras, diagramas, topos = [], [], []
    nombre = None
    for fich in ('README.md', 'practica.md', 'ejercicios.md', 'soluciones.md'):
        p = os.path.join(RAIZ, carpeta, fich)
        if not os.path.exists(p): continue
        L = open(p).read().split('\n')
        vistos, seccion, anc, topo, i = {}, '', '', None, 0
        while i < len(L):
            l = L[i]
            if re.match(r'#{1,6} ', l) and not l.startswith('#!'):
                seccion = l.lstrip('#').strip(); anc = ancla(seccion, vistos)
                if l.startswith('# ') and fich == 'README.md' and not nombre: nombre = seccion
            m = re.match(r'<!-- topologia:inicio\s*(\S*)\s*-->', l)
            if m:
                topo = m.group(1) or 'lab'
                if fich == 'README.md':
                    topos.append((topo, f'{carpeta}/{fich}#{anc}', f'{carpeta}/{topo}/topologia.drawio' if topo != 'lab' else f'{carpeta}/lab/topologia.drawio'))
            if l.startswith('<!-- topologia:fin'): topo = None
            for alt, ruta in re.findall(r'!\[([^\]]*)\]\((img/[^)]+)\)', l):
                figuras.append((alt, f'{carpeta}/{ruta}', f'{carpeta}/{fich}#{anc}', seccion))
            if l.startswith('```mermaid') and topo is None:
                j = i + 1
                while not L[j].startswith('```'): j += 1
                cuerpo = [x for x in L[i + 1:j] if x.strip()]
                titulo = cuerpo[0][2:].strip() if cuerpo and cuerpo[0].startswith('%%') else seccion
                tipo = next((x.split()[0] for x in cuerpo if not x.startswith('%%')), '')
                diagramas.append((titulo, TIPOS.get(tipo, tipo), f'{carpeta}/{fich}#{anc}', seccion))
                i = j
            i += 1
    return nombre or carpeta, figuras, diagramas, topos


def main():
    datos = [(c,) + recorrer(c) for c in carpetas()]
    corto = lambda c: c.split('/')[-1].split('-')[0] if c.startswith('anexo') else c[:2]
    etiqueta = lambda c, n: ('Base' if c.endswith('topologia-base') else corto(c)) + ' · ' + re.sub(r'^(\d\d|E\d+) · ', '', n)
    out = ['# 🗺️ Índice de esquemas, diagramas y topologías', '',
           'Todo lo que se puede **ver** en el curso, en un solo sitio: cada entrada enlaza a la sección donde se explica.', '',
           '- [Figuras](#figuras): formatos de cabeceras, paquetes y direcciones (SVG).',
           '- [Diagramas](#diagramas): el viaje de un paquete, estados y grafos (Mermaid).',
           '- [Topologías de los laboratorios](#topologías-de-los-laboratorios): el esquema de cada laboratorio, con su fichero de draw.io.', '',
           '> Este índice lo genera `python3 herramientas/indice-esquemas.py`. Las figuras SVG salen de `herramientas/esquemas.py`, y los esquemas de topología, de `herramientas/topologia.py`. Si añades un diagrama, vuelve a ejecutar el script.', '',
           '## Figuras', '', '| | Figura | Dónde |', '|---|---|---|']
    for c, n, figs, _, _ in datos:
        for alt, ruta, enlace, sec in figs:
            out.append(f'| <a href="{ruta}"><img src="{ruta}" width="260"></a> | **{alt}** | [{etiqueta(c, n)}]({enlace})<br/>{sec} |')
    out += ['', '## Diagramas', '', '| Diagrama | Tipo | Dónde |', '|---|---|---|']
    for c, n, _, diags, _ in datos:
        for titulo, tipo, enlace, sec in diags:
            out.append(f'| [{titulo}]({enlace}) | {tipo} | {etiqueta(c, n)} · {sec} |')
    out += ['', '## Topologías de los laboratorios', '', '| Módulo o escenario | Laboratorio | Esquema | draw.io |', '|---|---|---|---|']
    for c, n, _, _, topos in datos:
        for lab, enlace, drawio in topos:
            dr = f'[editar]({drawio})' if os.path.exists(os.path.join(RAIZ, drawio)) else '—'
            out.append(f'| {etiqueta(c, n)} | `{lab}` | [ver]({enlace}) | {dr} |')
    open(os.path.join(RAIZ, 'ESQUEMAS.md'), 'w').write('\n'.join(out) + '\n')
    nf = sum(len(d[2]) for d in datos); nd = sum(len(d[3]) for d in datos); nt = sum(len(d[4]) for d in datos)
    print(f'✔ ESQUEMAS.md: {nf} figuras, {nd} diagramas, {nt} topologías')


if __name__ == '__main__':
    main()
