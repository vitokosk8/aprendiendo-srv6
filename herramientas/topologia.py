#!/usr/bin/env python3
"""Genera el esquema de conexionado de un laboratorio a partir de su lab.clab.yml.

Produce dos salidas con la misma información (nodos, interfaces, direcciones y SIDs):

  * lab/topologia.drawio  → editable en draw.io / VS Code, exportable a PNG/PDF
  * el bloque Mermaid de practica.md, entre los marcadores
      <!-- topologia:inicio --> y <!-- topologia:fin -->

Uso:
  python3 herramientas/topologia.py 01-direccion-ipv6/lab/lab.clab.yml

Requiere PyYAML (pip3 install pyyaml).

Los datos se leen de las etiquetas (labels) de cada nodo en lab.clab.yml:

  graph-level: 2                      orden de izquierda a derecha
  graph-row: 1                        fila dentro de su columna (opcional, por defecto 1, 2, 3…)
  graph-icon: router | host           icono
  ip.lo: "3fff:0:ff::1/128"           dirección de cada interfaz (ip.<interfaz>)
  ip.eth1: "3fff:0:1::1/64"           varias direcciones separadas por comas;
  ip.eth2: "SLAAC"                    o un texto libre, como "SLAAC"
  srv6.locator: "5f00:0:1::/48"       locator SRv6
  srv6.sids: "5f00:0:1:e000:: End.DT6; 5f00:0:1:e001:: End"   SIDs y su behavior
"""
import base64
import html
import ipaddress
import os
import re
import sys

import yaml

# ---------------------------------------------------------------------------
# Lectura del laboratorio
# ---------------------------------------------------------------------------

def load_lab(path):
    with open(path) as f:
        lab = yaml.safe_load(f)
    topo = lab["topology"]
    defaults = topo.get("defaults", {})
    nodes = {}
    for name, n in topo["nodes"].items():
        n = n or {}
        labels = {str(k): str(v) for k, v in (n.get("labels") or {}).items()}
        image = n.get("image", defaults.get("image", ""))
        icon = labels.get("graph-icon") or ("router" if "frr" in image else "host")
        role = {"router": "router", "host": "host"}.get(icon, icon)
        soft = "FRR" if "frr" in image else image.split("/")[-1].split(":")[0]
        ips = {k[3:]: [a.strip() for a in v.split(",")] for k, v in labels.items() if k.startswith("ip.")}
        sids = [s.strip() for s in labels.get("srv6.sids", "").split(";") if s.strip()]
        nodes[name] = {
            "name": name,
            "icon": icon,
            "desc": f"{role} · {soft}",
            "level": int(labels.get("graph-level", 1)),
            "row": int(labels["graph-row"]) if "graph-row" in labels else None,
            "ips": ips,
            "locator": labels.get("srv6.locator"),
            "sids": sids,
        }
    links = []
    for l in topo.get("links", []):
        (a, ai), (b, bi) = (e.split(":") for e in l["endpoints"])
        links.append((a, ai, b, bi))
    return lab["name"], nodes, links


def subnet(nodes, a, ai, b, bi):
    """Prefijo del enlace, deducido de la primera dirección con longitud de prefijo."""
    for n, i in ((a, ai), (b, bi)):
        for addr in nodes[n]["ips"].get(i, []):
            try:
                net = ipaddress.ip_interface(addr).network
                if net.prefixlen < 128:
                    return str(net)
            except ValueError:
                pass
    return ""


def iface_text(node, iface):
    addrs = node["ips"].get(iface, [])
    return [iface] + addrs


# ---------------------------------------------------------------------------
# Iconos (SVG incrustado en el .drawio, así se ve igual en cualquier sitio)
# ---------------------------------------------------------------------------

ICONS = {
    "router": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<circle cx="32" cy="32" r="30" fill="#ddf4ff" stroke="#0969da" stroke-width="2.5"/>
<g fill="none" stroke="#0969da" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
<path d="M16 25 H48 M41 18 L48 25 L41 32"/><path d="M48 39 H16 M23 32 L16 39 L23 46"/></g></svg>""",
    "host": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<rect x="2" y="2" width="60" height="60" rx="14" fill="#dafbe1" stroke="#1a7f37" stroke-width="2.5"/>
<g fill="none" stroke="#1a7f37" stroke-width="2.8" stroke-linecap="round">
<rect x="14" y="16" width="36" height="24" rx="3"/><path d="M32 40 V47 M23 49 H41"/></g></svg>""",
}


def icon_style(kind):
    svg = ICONS.get(kind, ICONS["host"])
    b64 = base64.b64encode(svg.encode()).decode()
    return ("shape=image;aspect=fixed;imageAspect=0;html=1;verticalLabelPosition=bottom;"
            "verticalAlign=top;labelBackgroundColor=none;fontFamily=Helvetica;fontColor=#1f2328;"
            "strokeColor=none;fillColor=none;"
            f"image=data:image/svg+xml,{b64};")


# ---------------------------------------------------------------------------
# draw.io
# ---------------------------------------------------------------------------

MONO = "font-family:Menlo,Consolas,monospace"


def node_html(n):
    out = [f'<b style="font-size:15px">{n["name"]}</b>',
           f'<span style="color:#59636e;font-size:11px">{n["desc"]}</span>']
    lo = n["ips"].get("lo")
    if lo:
        out.append(f'<span style="{MONO};font-size:11px">lo {", ".join(lo)}</span>')
    if n["locator"]:
        out.append(f'<span style="{MONO};font-size:11px;color:#0969da">locator {n["locator"]}</span>')
    for s in n["sids"]:
        out.append(f'<span style="{MONO};font-size:11px;color:#bc4c00">SID {html.escape(s)}</span>')
    return "<br>".join(out)


def drawio(title, nodes, links):
    X0, Y0, DX, DY, ICON = 60, 110, 380, 300, 64
    # posiciones
    cols = {}
    for n in nodes.values():
        cols.setdefault(n["level"], []).append(n)
    for lvl, ns in cols.items():
        ns.sort(key=lambda n: (n["row"] or 0))
        for i, n in enumerate(ns):
            row = (n["row"] - 1) if n["row"] else i
            n["x"] = X0 + (lvl - 1) * DX
            n["y"] = Y0 + row * DY
    cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    esc = lambda s: html.escape(s, quote=True)
    cells.append(
        f'<mxCell id="title" value="{esc("<b>" + title + "</b>")}" '
        'style="text;html=1;align=left;verticalAlign=middle;fontSize=16;fontFamily=Helvetica;fontColor=#1f2328;strokeColor=none;fillColor=none;" '
        f'vertex="1" parent="1"><mxGeometry x="{X0 - 20}" y="20" width="600" height="30" as="geometry"/></mxCell>')
    for n in nodes.values():
        cells.append(
            f'<mxCell id="n-{n["name"]}" value="{esc(node_html(n))}" style="{icon_style(n["icon"])}" '
            f'vertex="1" parent="1"><mxGeometry x="{n["x"]}" y="{n["y"]}" width="{ICON}" height="{ICON}" as="geometry"/></mxCell>')
    lab_style = ("edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;points=[];"
                 "fontSize=11;fontFamily=Helvetica;fontColor=#1f2328;labelBackgroundColor=#ffffff;")
    for k, (a, ai, b, bi) in enumerate(links):
        eid = f"l{k}"
        cells.append(
            f'<mxCell id="{eid}" style="endArrow=none;html=1;strokeWidth=2;strokeColor=#8c959f;rounded=0;" '
            f'edge="1" parent="1" source="n-{a}" target="n-{b}"><mxGeometry relative="1" as="geometry"/></mxCell>')
        for pos, node, iface in ((-0.62, a, ai), (0.62, b, bi)):
            t = iface_text(nodes[node], iface)
            v = f'<b>{t[0]}</b>' + "".join(f'<br><span style="{MONO}">{x}</span>' for x in t[1:])
            cells.append(
                f'<mxCell id="{eid}-{node}" value="{esc(v)}" style="{lab_style}" vertex="1" connectable="0" parent="{eid}">'
                f'<mxGeometry x="{pos}" y="0" relative="1" as="geometry"><mxPoint as="offset"/></mxGeometry></mxCell>')
        net = subnet(nodes, a, ai, b, bi)
        if net:
            v = f'<span style="{MONO};color:#0969da">{net}</span>'
            cells.append(
                f'<mxCell id="{eid}-net" value="{esc(v)}" style="{lab_style}labelBackgroundColor=#ddf4ff;" vertex="1" connectable="0" parent="{eid}">'
                f'<mxGeometry x="0" y="-26" relative="1" as="geometry"><mxPoint as="offset"/></mxGeometry></mxCell>')
    body = "\n        ".join(cells)
    return f'''<mxfile host="aprendiendo-srv6">
  <diagram id="topologia" name="Topología">
    <mxGraphModel grid="1" gridSize="10" guides="1" page="0" math="0" shadow="0">
      <root>
        {body}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
'''


# ---------------------------------------------------------------------------
# Mermaid
# ---------------------------------------------------------------------------

def mermaid(nodes, links):
    out = ["```mermaid", "graph LR"]
    for n in sorted(nodes.values(), key=lambda n: (n["level"], n["row"] or 0)):
        lines = [f"<b>{n['name']}</b>", n["desc"]]
        for iface, addrs in n["ips"].items():
            lines.append(f"{iface}: {', '.join(addrs)}")
        if n["locator"]:
            lines.append(f"locator {n['locator']}")
        lines += [f"SID {s}" for s in n["sids"]]
        emoji = "🖥️ " if n["icon"] == "host" else ""
        label = emoji + "<br/>".join(lines)
        out.append(f'    {n["name"]}("{label}")')
    out.append("")
    for a, ai, b, bi in links:
        net = subnet(nodes, a, ai, b, bi)
        txt = f"{ai} ⟷ {bi}" + (f"<br/>{net}" if net else "")
        out.append(f'    {a} -- "{txt}" --- {b}')
    out += ["",
            "    classDef router fill:#ddf4ff,stroke:#0969da,stroke-width:2px,color:#1f2328",
            "    classDef host fill:#dafbe1,stroke:#1a7f37,stroke-width:2px,color:#1f2328"]
    for kind in ("router", "host"):
        names = [n["name"] for n in nodes.values() if n["icon"] == kind]
        if names:
            out.append(f"    class {','.join(names)} {kind}")
    out.append("```")
    return "\n".join(out)


# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    clab = sys.argv[1]
    labdir = os.path.dirname(os.path.abspath(clab))
    name, nodes, links = load_lab(clab)
    title = f"Topología del laboratorio · {name}"

    out = os.path.join(labdir, "topologia.drawio")
    with open(out, "w") as f:
        f.write(drawio(title, nodes, links))
    print(f"✔ {os.path.relpath(out)}")

    practica = os.path.join(os.path.dirname(labdir), "practica.md")
    if os.path.exists(practica):
        txt = open(practica).read()
        pat = re.compile(r"(<!-- topologia:inicio -->\n)(?:.*?\n)?(<!-- topologia:fin -->)", re.S)
        if pat.search(txt):
            txt = pat.sub(lambda m: m.group(1) + mermaid(nodes, links) + "\n" + m.group(2), txt)
            open(practica, "w").write(txt)
            print(f"✔ {os.path.relpath(practica)} (bloque Mermaid actualizado)")
        else:
            print(f"· {os.path.relpath(practica)} no tiene marcadores <!-- topologia:inicio/fin -->")


if __name__ == "__main__":
    main()
