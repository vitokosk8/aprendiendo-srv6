# 11 · Soluciones

> Las salidas de comandos son orientativas y se ajustarán con las de una ejecución real del laboratorio. Los valores de función de los SIDs (`func-bits`) los **asigna FRR dinámicamente**, así que las direcciones concretas de los `End`/`End.X` variarán entre despliegues.

## Parte A

**A1.** Un **locator** es el prefijo IPv6 (`/48`) propiedad de un router, dentro del cual viven todos sus SIDs. Partes:
- **block-len 32**: el bloque común a toda la red (los 32 bits altos).
- **node-len 16**: identifican al nodo (r1 = `0001`).
- **func-bits 16**: el espacio donde el router **asigna una función** a cada SID que crea (su `End`, cada `End.X`, etc.). Es, literalmente, el catálogo de "instrucciones" que ese router puede ofrecer.

**A2.** Dos tipos:
- **prefix-SID → `End`**: uno por nodo; representa "pasa por este router". Es el bloque básico de cualquier camino.
- **adjacency-SID → `End.X`**: uno por adyacencia; representa "sal por este enlace concreto". Base de la ingeniería de tráfico.

**A3.** 
- **r2**: tiene **dos** adyacencias (con r1 y con r3), así que **dos** `End.X`.
- **r1**: tiene **una** adyacencia de núcleo (con r2) → **un** `End.X`. (El enlace hacia h1 es `passive`: no forma adyacencia IS-IS, así que no genera End.X.)

**A4.** Porque si el locator estuviera como dirección en `lo`, el kernel crearía la **anycast de subred** (la dirección base del `/48`) en la tabla `local`, que se consulta antes que la main e **interceptaría** los paquetes dirigidos a esa base (justo el problema del módulo 10). Instalándolo como ruta **`seg6local` sobre `sr0`**, la base del locator no es una dirección local del nodo, y el behavior la procesa siempre. FRR hace bien de fábrica lo que a mano tuvimos que corregir borrando la anycast.

**A5.** Falta un SID de **servicio**: `End.DT4` / `End.DT6` / `End.DT46` (o `End.DX4`/`DX6`), que desencapsula y entrega el tráfico del cliente a su VPN. Lo aporta **BGP** (módulo 12): el IGP da el transporte; BGP, el servicio.

## Parte B

### B1
1. `MAIN` tiene prefijo `5f00:0:1::/48`, con `block-len 32`, `node-len 16`, `func-bits 16`.
2. Aparecen los SIDs que IS-IS ha asignado dentro del locator: el `End` del nodo y los `End.X` de sus adyacencias (con sus valores de función concretos, asignados por FRR).

### B2
1. Sobre **`sr0`** (la interfaz dummy), no sobre `lo`.
2. Verás un `action End` (el del locator/nodo) y uno o más `action End.X` (las adyacencias). En **r2** hay **dos** `End.X` (hacia r1 y hacia r3), coincidiendo con A3.
3. Esta vez las escribió **FRR** (IS-IS), no tú. En los módulos 08-10 cada una era un `ip -6 route add ... encap seg6local ...` a mano.

### B3
1. Sí: `show isis segment-routing srv6 node` lista a r2 y r3 con sus locators.
2. La ruta a `5f00:0:3::/48` sale por `eth2` (hacia r2) y se aprendió por **IS-IS** (proto `isis` / `115`). Es el anuncio del locator de r3 propagado por el IGP.
3. Porque para enviar tráfico a **cualquier** SID de r3 (su `End`, un `End.X`, o mañana un `End.DT` de servicio), los demás routers necesitan saber enrutar hacia su locator `/48`. Sin ese anuncio, los SIDs de r3 serían inalcanzables.

### B4
1. Sí funcionan: es el transporte IPv6 por IS-IS (como en el módulo 05). Aún no es un camino SRv6 de cliente de extremo a extremo, porque falta el SID de servicio.

### B5
1. Sí funciona. El transporte hasta `5f00:0:3:dc04::` lo resolvió **FRR**: tú no pusiste ninguna ruta hacia el locator de r3; el paquete IPv6 exterior (destino `5f00:0:3:dc04::`, dentro de `5f00:0:3::/48`) se enruta por el IGP gracias al anuncio del locator. Tú solo pusiste el **servicio** (el `End.DX4`) y el encap.
2. Porque con **un** solo SID de servicio, el núcleo enruta el paquete IPv6 exterior hacia el locator de r3 por el camino más corto del IGP (r1→r2→r3): no hacen falta SIDs de tránsito explícitos. r2 reenvía el IPv6 sin procesar ningún SID. (Si quisieras forzar un camino concreto, añadirías End.X de tránsito, como en B6.)
3. BGP automatizará el **servicio**: asignar el SID `End.DT4`/`DT6` en el PE de destino, meter la red del cliente en una VRF y anunciar por BGP "para esta VPN, encapsula hacia este SID". Eso es la L3VPN SRv6 del módulo 12.

### B6
1. Sí sigue funcionando: ahora el salto r2→r3 va forzado por el `End.X` de r2, no por el IGP.
2. Se notaría si r2 tuviera **dos** caminos hacia r3 (p. ej. un enlace directo y otro por un cuarto router): con el `End` normal el IGP elegiría el más corto; con el `End.X` fuerzas el enlace que tú decidas. Esa es la base de la ingeniería de tráfico (módulo 14).
3. (Se restaura el encap con `ip route replace ... segs 5f00:0:3:dc04::`.)

### Reto
1. El LSP lleva la **SRv6 Capabilities** del nodo (que soporta SRv6, el tamaño máximo de SID, etc.) y los **SRv6 Locator TLV** con el prefijo del locator y los End-SID; los End.X van como sub-TLV de las adyacencias. Es lo que define el [RFC 9352](https://www.rfc-editor.org/rfc/rfc9352.html).
2. Porque el IGP **ya calcula la topología y el camino más corto** a cada prefijo. Añadir los locators/SIDs a sus anuncios es casi gratis y garantiza que el transporte SRv6 sigue exactamente la misma visión de la red que el enrutamiento normal, sin un protocolo aparte que mantener sincronizado.
3. Que el SID es una **dirección IPv6 enrutable normal**: cualquier router (aunque no "entienda" SRv6) sabe reenviar hacia el locator `/48` con su tabla IPv6 de siempre. No hace falta un plano de etiquetas MPLS ni que todos los nodos soporten SR; los nodos intermedios "tontos" reenvían el paquete como IPv6 corriente. Eso facilita el despliegue incremental.
