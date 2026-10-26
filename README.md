<div align="center">

# 🧭 Aprendiendo SRv6

**Curso práctico de Segment Routing over IPv6 (SRv6), en español y desde cero.**

De *"¿qué es una dirección IPv6?"* a montar **L3VPN multicliente con ingeniería de tráfico, resiliencia y operación segura** — todo con software libre, en tu portátil.

![Licencia](https://img.shields.io/badge/licencia-CC%20BY--SA%204.0-blue)
![Idioma](https://img.shields.io/badge/idioma-español-green)
![Lab](https://img.shields.io/badge/lab-Containerlab-00b0f0)
![Routing](https://img.shields.io/badge/routing-FRRouting%2010.7-cc0000)
![Data plane](https://img.shields.io/badge/data%20plane-SRv6%20(Linux%20kernel)-5f3aa6)
![Módulos](https://img.shields.io/badge/módulos-19%20(00→18)-success)

</div>

---

Cada módulo combina **teoría**, un **laboratorio reproducible** con [Containerlab](https://containerlab.dev) y [FRRouting](https://frrouting.org), y **prácticas con soluciones**. No hace falta ninguna imagen de fabricante: SRv6 vive en el **kernel de Linux** y el plano de control en **FRR**. Todo lo que se explica, se monta y se comprueba.

> 💡 El curso es **honesto** con lo que el software libre soporta hoy: cuando FRR/Linux no cubre algo (p. ej. SR-TE, TI-LFA o Flex-Algo sobre SRv6), se explica la teoría completa, se demuestra lo que **sí** es practicable, y se indica con qué plataforma se haría en producción.

## 🎯 Qué vas a aprender

- **IPv6 a fondo**: direcciones, cabecera y cabeceras de extensión, ICMPv6/ND, enrutamiento e IS-IS.
- **El plano de datos SRv6**: el SID, la SRH, y todo el catálogo de *behaviors* (`End`, `End.X`, `End.DT4/DT6/DT46`, `End.DX4/DX6`, `H.Encaps`), montados **a mano** con `iproute2` para entender qué hace cada uno.
- **Eficiencia**: reducción de cabeceras (`H.Encaps.Red`, flavors `PSP/USP/USD`) y **compresión uSID** (NEXT-C-SID).
- **El plano de control con FRR**: IS-IS que anuncia *locators* e instala SIDs solo, y **BGP** que monta **L3VPN** IPv4, IPv6 y dual-stack (`End.DT4/DT6/DT46`).
- **Ingeniería de tráfico y resiliencia**: listas de segmentos explícitas, SR Policy, TI-LFA y **Flex-Algo** (varios caminos más cortos sobre la misma red, la base del *network slicing*).
- **Operación**: OAM, *troubleshooting*, MTU y seguridad/filtrado en el borde.
- **Próximamente**: multicast en redes SRv6 (BIER) y un anexo de escenarios con casos de uso completos.

Y, de propina, el **porqué** de cada cosa: de MPLS a SR, el modelo de confianza del dominio, y las trampas reales de montar SRv6 en Linux (que irás descubriendo lab a lab).

## 🚀 Cómo usar este repositorio

Cada módulo es una carpeta con la misma estructura (plantilla en [`herramientas/plantilla-modulo`](herramientas/plantilla-modulo)):

```
NN-tema/
├── README.md        ← teoría, con el esquema del laboratorio al principio
├── practica.md      ← ejercicios guiados sobre el laboratorio
├── soluciones.md    ← soluciones razonadas (¡inténtalo antes!)
└── lab/             ← topología de Containerlab y configuraciones
    ├── lab.clab.yml
    ├── verificar.sh ← comprueba que el laboratorio hace lo que debe
    └── rN/…         ← configuraciones de FRR por router
```

1. Prepara el entorno una sola vez: **[00 · Preparación del entorno](00-preparacion/README.md)**.
2. Lee la teoría del módulo (`README.md`).
3. Levanta el laboratorio (`sudo containerlab deploy -t lab/lab.clab.yml`) y pásale `lab/verificar.sh`.
4. Haz la práctica y compárala con las soluciones.
5. Destruye el laboratorio (`sudo containerlab destroy ... --cleanup`) antes del siguiente.

Los módulos se siguen **en orden**: cada uno se apoya en lo aprendido en los anteriores.

## 📚 Temario

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
| [07](07-sid-srh/README.md) | El SID y la Segment Routing Header (SRH) | ✅ |
| [08](08-network-programming/README.md) | Network programming con iproute2: End, End.X, End.DT4/DT6/DT46, H.Encaps | ✅ |
| [09](09-reduccion-cabeceras/README.md) | Reducción de cabeceras: H.Encaps.Red y los flavors PSP/USP/USD | ✅ |
| [10](10-usid/README.md) | uSID: SIDs comprimidos (NEXT-C-SID) | ✅ |

### Bloque III · Plano de control con FRR

| Módulo | Tema | Estado |
|--------|------|:------:|
| [11](11-isis-srv6/README.md) | IS-IS con SRv6: locators y SIDs End.X | ✅ |
| [12](12-l3vpn-bgp/README.md) | L3VPN IPv4 sobre SRv6 con BGP (End.DT4) | ✅ |
| [13](13-l3vpn-dualstack/README.md) | L3VPN IPv6 y dual-stack (End.DT6 / End.DT46) | ✅ |
| [14](14-te-srv6/README.md) | Ingeniería de tráfico con SRv6 | ✅ |
| [15](15-tilfa/README.md) | Resiliencia: TI-LFA | ✅ |
| [16](16-flex-algo/README.md) | Flex-Algo: varios caminos más cortos sobre la misma red (solo teoría: FRR no lo soporta con SRv6) | ✅ |

### Bloque IV · Operación

| Módulo | Tema | Estado |
|--------|------|:------:|
| [17](17-oam/README.md) | OAM y troubleshooting: ping, traceroute y capturas | ✅ |
| [18](18-mtu-seguridad/README.md) | MTU, seguridad y filtrado de SRv6 en el borde | ✅ |

### Bloque V · Multicast en redes SRv6 *(previsto)*

| Módulo | Tema | Estado |
|--------|------|:------:|
| 19 | El problema del multicast en Segment Routing y la replicación en el ingreso | ⏳ |
| 20 | *Replication segments* y Tree-SID ([RFC 9524](https://www.rfc-editor.org/rfc/rfc9524)) | 🔍 |
| 21 | BIER y BIERv6: teoría, simulador en Python y laboratorio P4 opcional | 🔍 |

### [Anexo · Escenarios: casos de uso con laboratorio](anexo-escenarios/README.md) *(en preparación)*

Casos de uso completos, inspirados en los que documentan los fabricantes y montados con FRR sobre una **[topología común](anexo-escenarios/topologia-base/README.md)** (2 PE y un núcleo de 4 P en malla parcial, con sedes de capa 3 y de capa 2). Cada escenario plantea el problema del cliente, el diseño y su solución primero con el camino más corto (**SRv6 BE**) y después con **ingeniería de tráfico**. Van numerados aparte (E0, E1…) para que los bloques de módulos puedan crecer sin renumerar nada.

| Escenario | Caso de uso | Estado |
|-----------|-------------|:------:|
| [Base](anexo-escenarios/topologia-base/README.md) | Topología común: núcleo SRv6 de 6 routers, sedes BLUE y VLAN 100 | ✅ |
| [E0](anexo-escenarios/E0-internet/README.md) | Internet sobre SRv6: núcleo sin BGP, con Internet en una VRF y en la tabla global | 🧪 |
| E1 | Cliente multisede: L3VPNv4, con UCMP, steering por color y P como route reflector | ⏳ |
| E2 | Dos operadores: Inter-AS L3VPNv4 | ⏳ |
| E3 | EVPN L3VPN IPv4 | 🔍 |
| E4 | EVPN L3VPN IPv6 | 🔍 |
| E5 | Línea punto a punto: EVPN VPWS | 🔍 |
| E6 | LAN extendida: EVPN VPLS | 🔍 |
| E7 | *Network slicing* | 🔍 |
| E8 | Compresión uSID en TE y migración desde SIDs clásicos, con islas SRv6 sobre GRE | ⏳ |
| E9 | *Service chaining* (SFC) | 🔍 |
| — | Lo que FRR aún no hace: egress protection, shortcuts, slicing con HBH, interworking con MPLS | ⏳ |

> ✅ escrito y probado · 🧪 escrito, pendiente de probar · ⏳ pendiente · 🔍 pendiente de verificar qué soporta FRR (si no lo soporta, solo teoría)

## 🧩 Convenciones

- **Direccionamiento**: `3fff::/20`, bloque de documentación del [RFC 9637](https://www.rfc-editor.org/rfc/rfc9637) (evitando `3fff:172::/32`, que usa la red de gestión de Containerlab). El módulo 01 usa además el clásico `2001:db8::/32` ([RFC 3849](https://www.rfc-editor.org/rfc/rfc3849)). Para los **SIDs**, `5f00::/16` ([RFC 9602](https://www.rfc-editor.org/rfc/rfc9602)).
- **Nombres**: `hN` para hosts, `rN` para routers.
- **Esquemas de red**: cada módulo muestra su topología con direcciones y SIDs en [Mermaid](https://mermaid.js.org) (que GitHub dibuja solo) y en un `lab/topologia.drawio` editable. Ambos se generan desde el `lab.clab.yml` con [`herramientas/topologia.py`](herramientas/topologia.py).
- **Prompts**: los comandos con `$` se ejecutan en tu máquina; los que empiezan por `h1#`, `r1#`… dentro del contenedor indicado.
- **Entorno de pruebas**: Containerlab 0.82.0 sobre OrbStack (kernel Linux 7.2), FRR 10.7.1 y netshoot v0.13. Cada laboratorio fija la imagen exacta con la que se probó, y [`herramientas/probar-todos.sh`](herramientas/probar-todos.sh) los levanta, verifica y destruye todos de una vez.

## 🛠️ Herramientas usadas

| Herramienta | Para qué |
|-------------|----------|
| [Containerlab](https://containerlab.dev) | Orquestar las topologías de laboratorio |
| [FRRouting](https://frrouting.org) (FRR 10.7) | Plano de control: IS-IS, BGP, SRv6 |
| Kernel Linux (`iproute2`, `seg6`/`seg6local`) | Plano de datos SRv6 |
| [netshoot](https://github.com/nicolaka/netshoot) | Hosts y herramientas de red (ping, traceroute, tcpdump, scapy) |
| [Mermaid](https://mermaid.js.org) + [draw.io](https://www.drawio.com) | Diagramas de topología |

## 📖 Referencias

Todo lo que se cita en los módulos, reunido aquí.

### IPv6 (fundamentos)
- [RFC 8200](https://www.rfc-editor.org/rfc/rfc8200) — Internet Protocol, Version 6 (IPv6) Specification
- [RFC 4291](https://www.rfc-editor.org/rfc/rfc4291) — IPv6 Addressing Architecture
- [RFC 4443](https://www.rfc-editor.org/rfc/rfc4443) — ICMPv6
- [RFC 4861](https://www.rfc-editor.org/rfc/rfc4861) — Neighbor Discovery for IPv6
- [RFC 4862](https://www.rfc-editor.org/rfc/rfc4862) — IPv6 Stateless Address Autoconfiguration (SLAAC)
- [RFC 8201](https://www.rfc-editor.org/rfc/rfc8201) — Path MTU Discovery for IPv6
- [RFC 3849](https://www.rfc-editor.org/rfc/rfc3849) — IPv6 Address Prefix Reserved for Documentation (`2001:db8::/32`)
- [RFC 9637](https://www.rfc-editor.org/rfc/rfc9637) — IPv6 Documentation Prefix (`3fff::/20`)

### Segment Routing y SRv6
- [RFC 8402](https://www.rfc-editor.org/rfc/rfc8402) — Segment Routing Architecture
- [RFC 8754](https://www.rfc-editor.org/rfc/rfc8754) — IPv6 Segment Routing Header (SRH)
- [RFC 8986](https://www.rfc-editor.org/rfc/rfc8986) — SRv6 Network Programming (catálogo de *behaviors*)
- [RFC 9602](https://www.rfc-editor.org/rfc/rfc9602) — SRv6 SID block (`5f00::/16`)
- [draft-ietf-spring-srv6-srh-compression](https://datatracker.ietf.org/doc/draft-ietf-spring-srv6-srh-compression/) — Compressed SRv6 Segment List Encoding (uSID / NEXT-C-SID)

### Plano de control (IS-IS / BGP)
- [RFC 9352](https://www.rfc-editor.org/rfc/rfc9352) — IS-IS Extensions to Support SRv6
- [RFC 8667](https://www.rfc-editor.org/rfc/rfc8667) — IS-IS Extensions for Segment Routing (SR-MPLS)
- [RFC 4364](https://www.rfc-editor.org/rfc/rfc4364) — BGP/MPLS IP VPNs (modelo CE/PE/P, RD/RT)
- [RFC 9252](https://www.rfc-editor.org/rfc/rfc9252) — BGP Overlay Services over SRv6
- [RFC 8950](https://www.rfc-editor.org/rfc/rfc8950) — Advertising IPv4 NLRI with IPv6 Next Hop (*extended-nexthop*)

### Ingeniería de tráfico y resiliencia
- [RFC 9256](https://www.rfc-editor.org/rfc/rfc9256) — Segment Routing Policy Architecture
- [RFC 9855](https://www.rfc-editor.org/rfc/rfc9855) — Topology Independent Loop-Free Alternate (TI-LFA)
- [RFC 5286](https://www.rfc-editor.org/rfc/rfc5286) — Basic Specification for IP Fast Reroute: LFA
- [RFC 9350](https://www.rfc-editor.org/rfc/rfc9350) — IGP Flexible Algorithm (Flex-Algo)
- [RFC 9843](https://www.rfc-editor.org/rfc/rfc9843) — IGP Flex-Algorithms: Bandwidth, Delay, Metrics and Constraints
- [RFC 8570](https://www.rfc-editor.org/rfc/rfc8570) — IS-IS Traffic Engineering Metric Extensions (retardo de enlace)
- [RFC 8919](https://www.rfc-editor.org/rfc/rfc8919) — IS-IS Application-Specific Link Attributes
- [RFC 7308](https://www.rfc-editor.org/rfc/rfc7308) — Extended Administrative Groups (afinidades)

### Operación (OAM)
- [RFC 9259](https://www.rfc-editor.org/rfc/rfc9259) — OAM in SRv6 Networks

### Comunidad y laboratorios
- [SRv6.md](https://srv6.md) — wiki comunitaria sobre SRv6 ([repositorio](https://github.com/eldaninavas/srv6.md))
- [segmentrouting/srv6-labs](https://github.com/segmentrouting/srv6-labs) — laboratorios SRv6 de referencia
- [SRv6 en el kernel de Linux (netdev 0x19, 2025)](https://www.segment-routing.net/images/20250311-srv6-usid-linux-netdev-0x19.pdf)
- [FRR · ISIS](https://docs.frrouting.org/en/latest/isisd.html) · [FRR · BGP](https://docs.frrouting.org/en/latest/bgp.html) · [FRR · PATH](https://docs.frrouting.org/en/latest/pathd.html)
- [Documentación del kernel: SRv6](https://docs.kernel.org/networking/seg6-sysctl.html)

## 👤 Autor

Creado por **Victor Bolaños Guerra** ([@vitokosk8](https://github.com/vitokosk8)) como material de formación abierta sobre SRv6.

## 📜 Licencia

Publicado bajo [**CC BY-SA 4.0**](LICENSE): puedes reutilizarlo y adaptarlo citando la fuente y manteniendo la misma licencia.
