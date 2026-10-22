# 05 · Soluciones

> Las salidas de comandos son orientativas y se ajustarán con las de una ejecución real del laboratorio.

## Parte A

**A1.**

```
49 . 0001 . 0000.0000.0002 . 00
│    │       │               └ NSEL: 00 (es un router)
│    │       └ System ID: 0000.0000.0002
│    └ Área: 0001
└ AFI: 49 (direccionamiento privado)
```

El System ID `0000.0000.0002` corresponde a **r2**.

**A2.** Porque IS-IS no viaja dentro de IP: va directamente sobre la capa 2 y transporta las direcciones (IPv4, IPv6…) como datos dentro de sus TLV. El protocolo no necesita cambiar para encaminar un tipo de dirección u otro. La ventaja para SRv6 es que **añadir SRv6 es solo definir TLV nuevos** (locator, SID), sin tocar el motor del protocolo; por eso IS-IS fue el primero y el más cómodo para Segment Routing.

**A3.** El coste de una **red** es el coste hasta el nodo que la anuncia **más** la métrica de la interfaz pasiva por la que la anuncia (10). Así que todos salen a **20**. El siguiente salto es la **link-local** del vecino, no su dirección global:

| Destino | Camino más corto | Coste | Sale por |
|---------|------------------|-------|----------|
| loopback de r2 | r1→r2 (10) + lo pasiva (10) | **20** | link-local de r2, por eth2 |
| loopback de r3 | r1→r3 (10) + lo pasiva (10) | **20** | link-local de r3, por eth3 |
| red de h2 | r1→r2 (10) + eth3 pasiva (10) | **20** | link-local de r2, por eth2 |
| red de h3 | r1→r3 (10) + eth3 pasiva (10) | **20** | link-local de r3, por eth3 |

(El coste al **nodo** r2 o r3 sí es 10; lo que suma 20 es el coste al **prefijo**, por la métrica de la interfaz pasiva. Son dos medidas distintas, como explica la teoría.)

**A4.** Con el enlace r1–r3 a métrica 30, el camino directo al loopback de r3 cuesta 30 + 10 (pasiva) = **40**; el camino por r2 cuesta 10 + 10 + 10 = **30**. Gana el de r2: r1 llegará al loopback de r3 **por r2** (link-local de r2, eth2), con coste 30.

**A5.** Porque IS-IS hace que **todos** los routers reconverjan, no solo uno. Al caer un enlace, los routers afectados generan un LSP nuevo sin ese enlace y lo inundan; r1, r2 y r3 actualizan su LSDB y recalculan SPF. El camino de vuelta se recalcula igual que el de ida, porque cada router rehace **todas** sus rutas. En el módulo 04, las rutas estáticas de r2 no se recalculaban solas, así que la vuelta quedaba rota.

## Parte B

### B1

```
Area CORE:
 System Id           Interface   L  State  Holdtime SNPA
 r2                  eth2        2  Up     29       2020.2020.2020
 r3                  eth3        2  Up     28       2020.2020.2020
```

1. Dos vecinos: **r2** (por eth2) y **r3** (por eth3).
2. En estado **Up** (adyacencia establecida), en el nivel **2**. Cada una por la interfaz que conecta con ese vecino. El `SNPA` es la MAC del vecino en enlaces punto a punto (un valor fijo que pone FRR).
3. Porque eth1 (hacia h1) está configurada como **pasiva** (`isis passive`). Una interfaz pasiva **anuncia su red** en IS-IS pero **no envía Hello** ni forma adyacencias. Así la red de h1 entra en el mapa sin intentar "hacer IS-IS" con un host que no lo habla. Es lo correcto para toda interfaz hacia clientes o LAN de acceso.

### B2

1. **Tres** LSP: `r1.00-00`, `r2.00-00` y `r3.00-00`, uno por router.
2. **Sí**, son iguales (mismos LSP con el mismo número de secuencia). Deben serlo porque la LSDB es el mapa compartido: cuando la red ha convergido, todos los routers tienen una copia idéntica. Es la base del estado de enlace.
3. En el `detail` de `r3.00-00` verás:
   - **Extended Reachability** a `r1` y a `r2`, cada una con `Metric: 10`: son sus adyacencias.
   - **IPv6 Reachability** de `3fff:0:ff::3/128` (su loopback) y `3fff:0:3::/64` (la red de h3), entre otras. Sí aparecen las dos: son las redes que r3 anuncia.

### B3

```
I>* 3fff:0:2::/64   [115/20] via fe80::...(r2), eth2
I>* 3fff:0:3::/64   [115/20] via fe80::...(r3), eth3
I>* 3fff:0:23::/64  [115/20] via fe80::...(r2), eth2
  *                          via fe80::...(r3), eth3
I>* 3fff:0:ff::2/128 [115/20] via fe80::...(r2), eth2
I>* 3fff:0:ff::3/128 [115/20] via fe80::...(r3), eth3
```

1. r1 aprende por IS-IS (`I>*`): los loopbacks `3fff:0:ff::2/128` y `3fff:0:ff::3/128`, las redes de host `3fff:0:2::/64` y `3fff:0:3::/64`, y el enlace `3fff:0:23::/64`. **Todas con coste 20**: el `115` de `[115/X]` es la distancia administrativa de IS-IS y el `20` es el coste SPF (10 del enlace + 10 de la interfaz pasiva que anuncia cada prefijo). El siguiente salto es siempre una **link-local** (`fe80::…`), no la dirección global del vecino.
2. Al loopback de r3 llega **por eth3**, el enlace directo (coste 20), que es más barato que el camino por r2 (30). Coincide con A3.
3. `show isis route` muestra el árbol SPF con el coste a cada **nodo**: **r3 a coste 10** y **r2 a coste 10** (los dos a un salto directo). Fíjate en la diferencia con el punto 1: al nodo r3 se llega a 10, pero a su loopback (un prefijo) a 20, porque el prefijo añade la métrica de la interfaz pasiva.

> **Un ECMP que ya está ahí.** La red `3fff:0:23::/64` (el enlace r2–r3) aparece con **dos** siguientes saltos de coste 20: por r2 (r1→r2→enlace) y por r3 (r1→r3→enlace), los dos a 10 + 10. IS-IS instala las dos y reparte: es el mismo ECMP del módulo 04, calculado solo.

### B4

1. Con el enlace r1–r3 a métrica 30, r1 llega al loopback de r3 **por r2** (link-local de r2, eth2), con coste **30** (10 + 10 + 10 de la pasiva), más barato que los 40 del enlace directo (30 + 10).
2. Sí: el traceroute a `3fff:0:3::30` pasa ahora por r2 (`3fff:0:12::2` y después `3fff:0:23::3`). Coincide con A4 (la conclusión: va por r2).
3. —

### B5

1. El ping **no se interrumpe**; como mucho pierde **uno o dos paquetes** mientras IS-IS reconverge, y sigue. (La reconvergencia tarda un instante: detectar el fallo, inundar el LSP y recalcular SPF.)
2. Ahora h1 llega a h3 **por r2**: el traceroute pasa por `3fff:0:12::2` y `3fff:0:23::3`. La ruta en r1 es `3fff:0:3::/64 via fe80::…(r2), eth2`, con coste 30. Recalcularon **todos**: r1 (perdió un vecino), y también r2 y r3 al recibir los LSP nuevos.
3. La vuelta de h3 a h1 también pasa ahora por r2 y **funciona**, porque r3 recalculó su ruta a `3fff:0:1::/64` igual que r1 recalculó la suya. Esto es exactamente lo que fallaba en el módulo 04: allí las rutas estáticas de r2/r3 no se recalculaban y la vuelta se rompía.
4. Al levantar el enlace, el camino directo (coste 10) vuelve a ganar y h1→h3 vuelve a ir por r1→r3. En todo el proceso (caída + recuperación) se pierden solo unos pocos paquetes.

### B6

1. r1 envía un Hello (`p2p IIH`) cada **10 segundos** por defecto. Además verás `lsp` (los Link State PDU que se inundan y refrescan) y `csnp`/`psnp` (los mensajes de sincronización de la base de datos).
2. **No** hay direcciones IPv6 en estas tramas: IS-IS viaja **directamente sobre la capa 2**, no dentro de IP. `tcpdump` las reconoce por el formato OSI, no por un filtro `ip6`. Por eso el filtro de captura es `isis`, no una dirección.

### Reto

El camino por r2 (`r1→r2→r3`) cuesta 10 + 10 = **20**. Para igualarlo, el enlace directo r1–r3 debe costar también **20**. Configura `isis metric 20` en eth3 de r1 y en eth1 de r3. Entonces los dos caminos a la red de h3 cuestan 20, e IS-IS instala **dos** siguientes saltos:

```
I>* 3fff:0:3::/64 [115/30] via fe80::...(r3), eth3
  *                        via fe80::...(r2), eth2
```

Con el directo a 20, el camino directo a la red de h3 cuesta 20 + 10 (pasiva) = 30, y el camino por r2 cuesta 10 + 10 + 10 = 30: los dos a **30**, de ahí el `[115/30]` con dos siguientes saltos. `show ipv6 route 3fff:0:3::/64` muestra las dos líneas con `*`, y el kernel lo instala como ruta multipath. Es el mismo ECMP del módulo 04, pero calculado solo por IS-IS.
