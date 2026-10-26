# Anexo · Escenarios: casos de uso con laboratorio

Los módulos del curso enseñan **cada pieza** de SRv6 por separado. Este anexo las junta en **casos de uso completos**, como los que resuelve un operador: un cliente con un problema, un diseño con SRv6 que lo resuelve y un laboratorio que demuestra que funciona.

Los escenarios están inspirados en los ejemplos de configuración que publican los fabricantes, pero **rehechos desde cero con FRR** y explicados paso a paso. Van numerados aparte (E0, E1…) para que los bloques de módulos puedan seguir creciendo sin renumerar nada.

## La topología base

Todos los escenarios usan la misma red: un núcleo SRv6 de **seis routers en malla parcial**, dos PE (r1 y r6) con una sede de capa 3 (**BLUE**) y una de capa 2 (**VLAN 100**) en cada extremo. Cada escenario configura sus servicios sobre ella y, si los necesita, añade equipos en unos **puntos de enganche** fijos (un router de Internet, un segundo AS, una tercera sede…).

➡️ **[Topología base: esquema, direccionamiento, métricas y laboratorio](topologia-base/README.md)**

## Cómo está hecho cada escenario

Todos siguen la misma estructura ([plantilla](plantilla-escenario/README.md)):

| Sección | Qué contiene |
|---|---|
| **Requisitos previos** | Qué módulos hay que haber hecho y con qué versión de FRR se probó |
| **El caso de uso** | El cliente, su problema y lo que pide |
| **Criterios de éxito** | Lo que pide el cliente, escrito como comprobaciones concretas. El `verificar.sh` del laboratorio comprueba exactamente esa lista |
| **La solución con SRv6** | El diseño, con su esquema gráfico (Mermaid y draw.io) con direcciones y SIDs |
| **Decisiones de diseño** | Por qué cada elección (qué SID, qué behavior) y qué alternativa se descartó |
| **Camino más corto y TE** | La solución primero con SRv6 BE (el camino que elige el IGP) y después forzando otro camino con ingeniería de tráfico |
| **Lo que verás en el cable** | Una captura de referencia del paquete encapsulado, para comparar con la tuya |
| **Rómpelo y arréglalo** | Un fallo provocado, sus síntomas y cómo se diagnostica |
| **En producción** | Qué cambiaría en una red real y qué no hace FRR |

Y, como en los módulos, cada escenario tiene su **laboratorio** en `lab/`, una **práctica** guiada y sus **soluciones**.

## Escenarios

| Escenario | Caso de uso | Estado |
|-----------|-------------|:------:|
| [Base](topologia-base/README.md) | Topología común a todos los escenarios | ✅ |
| [E0](E0-internet/README.md) | Internet sobre SRv6: núcleo sin BGP, con Internet en una VRF y en la tabla global | ✅ |
| [E1](E1-multisede/README.md) | Cliente multisede: L3VPNv4 con route reflector y UCMP (color, en teoría) | ✅ |
| [E2](E2-inter-as/README.md) | Dos operadores: L3VPN Inter-AS, opción A (VRF contra VRF) y opción C con un túnel SRv6 de punta a punta | ✅ |
| [E3](E3-evpn/README.md) | EVPN sobre SRv6: L3 (IPv4 e IPv6), VPWS y VPLS en teoría, y el plano de datos de un VPWS (End.DX2) con laboratorio | 🧪 |
| E4 | *Network slicing* | 🔍 |
| E5 | Compresión uSID en TE y migración desde SIDs clásicos, con islas SRv6 sobre GRE | ⏳ |
| E6 | *Service chaining* (SFC) | 🔍 |
| E7 | Ingeniería de tráfico con controlador: la topología SRv6 por BGP-LS (FRR 10.7) y un mini-controlador en Python | 🔍 |
| — | Lo que FRR aún no hace: egress protection, shortcuts, slicing con HBH, interworking con MPLS | ⏳ |

> ✅ escrito y probado · 🧪 escrito, pendiente de probar · ⏳ pendiente · 🔍 pendiente de verificar qué soporta FRR (si no lo soporta, solo teoría)
