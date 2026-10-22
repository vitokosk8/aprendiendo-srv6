# Aprendiendo SRv6

Curso práctico de **Segment Routing over IPv6 (SRv6)** en español, desde cero.

Empieza explicando qué es una dirección IPv6 y termina montando servicios VPN sobre SRv6. Cada módulo combina **teoría**, un **laboratorio** reproducible con [Containerlab](https://containerlab.dev) y [FRRouting](https://frrouting.org), y **prácticas** con sus soluciones.

Todo funciona con software libre: no hace falta ninguna imagen de fabricante.

## Cómo usar este repositorio

Cada módulo es una carpeta con la misma estructura (hay una plantilla en [`herramientas/plantilla-modulo`](herramientas/plantilla-modulo)):

```
NN-tema/
├── README.md        ← teoría, con el esquema del laboratorio al principio
├── practica.md      ← ejercicios guiados sobre el laboratorio
├── soluciones.md    ← soluciones razonadas (¡inténtalo antes!)
└── lab/             ← topología de Containerlab y configuraciones
```

1. Prepara el entorno una sola vez: [00 · Preparación del entorno](00-preparacion/README.md).
2. Lee la teoría del módulo.
3. Levanta el laboratorio y haz la práctica.
4. Compara con las soluciones.
5. Destruye el laboratorio antes de pasar al siguiente.

Los módulos están pensados para seguirse en orden: cada uno usa lo aprendido en los anteriores.

## Temario

El estado indica qué módulos están ya escritos y probados.

### Bloque I · Fundamentos de IPv6

| Módulo | Tema | Estado |
|--------|------|:------:|
| [00](00-preparacion/README.md) | Preparación del entorno: Docker, Containerlab, FRR y netshoot | ✅ |
| [01](01-direccion-ipv6/README.md) | La dirección IPv6: formato, tipos y cómo la obtiene un equipo | ✅ |
| [02](02-cabecera-ipv6/README.md) | La cabecera IPv6 y las cabeceras de extensión | ✅ |
| [03](03-icmpv6-nd/README.md) | ICMPv6 y Neighbor Discovery | ✅ |
| [04](04-enrutamiento/README.md) | Enrutamiento IPv6: rutas estáticas y longest-prefix match | ✅ |
| [05](05-isis/README.md) | IS-IS para IPv6 | ✅ |

### Bloque II · Segment Routing sobre IPv6

| Módulo | Tema | Estado |
|--------|------|:------:|
| [06](06-mpls-a-sr/README.md) | De MPLS a Segment Routing: el porqué | ✅ |
| [07](07-sid-srh/README.md) | El SID y la Segment Routing Header (SRH) | 🧪 |
| 08 | Network programming con iproute2: End, End.X, End.DT4/DT6/DT46, H.Encaps | ⏳ |
| 09 | Reducción de cabeceras: H.Encaps.Red y los flavors PSP/USP/USD | ⏳ |
| 10 | uSID: SIDs comprimidos | ⏳ |

### Bloque III · Plano de control con FRR

| Módulo | Tema | Estado |
|--------|------|:------:|
| 11 | IS-IS con SRv6: locators y SIDs End.X | ⏳ |
| 12 | L3VPN IPv4 sobre SRv6 con BGP (End.DT4) | ⏳ |
| 13 | L3VPN IPv6 y dual-stack (End.DT6 / End.DT46) | ⏳ |
| 14 | Ingeniería de tráfico con SRv6 en FRR | 🔍 |
| 15 | Resiliencia: TI-LFA | 🔍 |

### Bloque IV · Operación

| Módulo | Tema | Estado |
|--------|------|:------:|
| 16 | OAM y troubleshooting: ping, traceroute y capturas | ⏳ |
| 17 | MTU, seguridad y filtrado de SRv6 en el borde | ⏳ |

✅ escrito y probado · 🧪 escrito, pendiente de probar · ⏳ pendiente · 🔍 pendiente de verificar qué soporta FRR (si no lo soporta, se explicará la teoría y se indicará con qué plataforma practicarlo)

## Convenciones

- **Direccionamiento**: se usa `3fff::/20`, el bloque reservado para documentación por el [RFC 9637](https://www.rfc-editor.org/rfc/rfc9637), evitando `3fff:172::/32`, que usa la red de gestión de containerlab. El módulo 01 usa además el bloque clásico `2001:db8::/32` ([RFC 3849](https://www.rfc-editor.org/rfc/rfc3849)). Para los SIDs se usa `5f00::/16` ([RFC 9602](https://www.rfc-editor.org/rfc/rfc9602)).
- **Nombres**: `hN` para hosts y `rN` para routers.
- **Esquemas de conexionado**: cada módulo muestra su laboratorio con direcciones y SIDs al principio de la teoría y en el enunciado de la práctica, en [Mermaid](https://mermaid.js.org), que GitHub dibuja directamente, y en un fichero `lab/topologia.drawio` editable. Ambos se generan desde `lab.clab.yml` con [`herramientas/topologia.py`](herramientas/topologia.py) (ver [módulo 00](00-preparacion/README.md#dibujar-la-topología)).
- **Versiones fijadas**: cada laboratorio indica la imagen exacta con la que se probó.
- **Entorno de pruebas**: containerlab 0.74.3 sobre OrbStack (kernel Linux 7.2), FRR 10.2.1 y netshoot v0.13.
- Los comandos que empiezan por `$` se ejecutan en tu máquina; los que empiezan por `h1#`, `r1#`… dentro del contenedor indicado.

## Fuentes

- [SRv6.md](https://srv6.md) — wiki comunitaria sobre SRv6 ([repositorio](https://github.com/eldaninavas/srv6.md))
- [segmentrouting/srv6-labs](https://github.com/segmentrouting/srv6-labs) — laboratorios SRv6 de referencia
- RFC citados en cada módulo

## Licencia

El contenido se publica bajo [CC BY-SA 4.0](LICENSE): puedes reutilizarlo y adaptarlo citando la fuente y manteniendo la misma licencia.
