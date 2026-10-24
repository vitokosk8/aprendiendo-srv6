# 16 · Soluciones

**1.** No del todo. El número de algoritmo (128–255) **no tiene significado propio**: lo que define un algoritmo es su **FAD** (*Flexible Algorithm Definition*), que dice qué **métrica** usa y qué **restricciones** aplica. En esta red, el 128 es "baja latencia" porque su FAD dice "métrica de retardo". En otra red, el 128 podría significar "evita los enlaces amarillos". Lo correcto sería decir: "aquí, el algoritmo 128 está definido como el de menor retardo".

**2.**

| Algoritmo | Camino r1 → r4 | Coste IGP | Retardo |
|:-:|---|:-:|:-:|
| 0 | r1 → r2 → r4 | **20** | 7 ms |
| 128 | r1 → r3 → r4 | 40 | **2 ms** |

El algoritmo 0 minimiza el coste IGP (20 frente a 40), y el 128 minimiza el retardo (2 ms frente a 7 ms). Dos caminos distintos hacia el mismo router.

**3.**

| Destino | Algoritmo | Sale por | Coste hasta r5 |
|---|:-:|---|:-:|
| `5f00:0:5::/48` | 0 | eth3, directo a r5 | 10 |
| `5f00:81:5::/48` | 129 | eth2, hacia r4 | 30 (10 + 20) |

Son distintas porque cada locator se calcula con el SPF **de su algoritmo**. El de r5 del algoritmo 0 usa la topología completa, y el enlace directo r2–r5 es el más barato. El del algoritmo 129 se calcula sobre la topología **podada**, sin el enlace ROJO r2–r5, así que r2 tiene que ir por r4. Desde r2, el mismo router de destino tiene dos rutas distintas según el bloque del destino.

**4.** El destino `5f00:80:5:1::` está dentro de `5f00:80:5::/48`, el locator del **algoritmo 128** de r5. Cada router reenvía por *longest-prefix match* sobre su ruta a ese locator, calculada por el SPF de retardo:

- **r1**: la ruta a `5f00:80:5::/48` sale por eth2, hacia **r3**.
- **r3**: sale por eth2, hacia **r4**.
- **r4**: sale por eth3, hacia **r5**.
- **r5**: el destino es uno de sus SIDs; ejecuta su behavior (por ejemplo, un `End.DT4`).

Camino: r1 → r3 → r4 → r5, con 3 ms de retardo. **No necesita SRH**: el camino no va escrito en el paquete, sino que está implícito en el locator del destino. Si r1 encapsula con `H.Encaps.Red` (módulo 09), el SID va solo en el destino de la cabecera exterior, sin SRH. Con `H.Encaps` normal, Linux añadiría una SRH de un solo SID, pero ese SID es el mismo que va en el destino: la SRH no aporta información de camino.

**5.** Sin r3, el algoritmo 128 solo puede usar r1, r2, r4 y r5:

- r1 → r2 → r5 = 22 ms
- r1 → r2 → r4 → r5 = 2 + 5 + 1 = **8 ms** ← gana

Nuevo camino: **r1 → r2 → r4 → r5, con 8 ms**. Los algoritmos 0 y 129 **no cambian**: r3 sigue participando en ellos, y de todos modos ninguno de sus caminos pasaba por r3. La participación es **por algoritmo**: un router puede estar en unos y no en otros.

**6.**

1. **Ninguno.** En el algoritmo 129 se poda el enlace ROJO r2–r5 y, ahora, también r4. A r5 solo llegaban el enlace r2–r5 (podado) y el r4–r5 (r4 podado). El locator `5f00:81:5::/48` es **inalcanzable** en el algoritmo 129.
2. r1 no tiene ruta al SID de la VRF SEGURA, así que las rutas de ese cliente **dejan de ser válidas** y su tráfico **se pierde**. **No** se va por el algoritmo 0: no existe esa vuelta atrás automática. Es intencionado, porque el algoritmo 0 pasaría por el enlace ROJO, que es justo lo que el cliente no quiere.
3. En el algoritmo 129, **r4 es un punto único de fallo**: todo camino hacia r5 que no use el enlace ROJO pasa por r4. Pasaría lo mismo si r4 se cayera de verdad. La solución es dar a r5 un **segundo camino sin ROJO que no pase por r4**: por ejemplo, un enlace r3–r5, o sustituir el circuito de terceros r2–r5 por uno propio sin la afinidad ROJO. Regla de diseño: **cada algoritmo tiene que tener redundancia dentro de su propia topología**, no basta con que la tenga la red física.

**7.** Cae r3–r4:

| Algoritmo | Camino r1 → r5 | Coste |
|:-:|---|---|
| 0 | r1 → r2 → r5 (no cambia) | 20 |
| 128 | r1 → r2 → r4 → r5 | 8 ms |
| 129 | r1 → r2 → r4 → r5 (no cambia) | 40 |

Solo cambia el algoritmo 128, que era el único que usaba ese enlace. Cada algoritmo reconverge por su cuenta.

**8.**

1. Con todo activo: r1 → r3 → r4 → r5, **3 ms**. Coincide con el algoritmo 128, porque el camino de menor retardo ya no usaba el enlace ROJO: la restricción no cambia nada… de momento.
2. Cae r4–r5. A r5 solo se llega por el enlace r2–r5:
   - **Algoritmo 128**: r1 → r2 → r5, **22 ms**. Es lento, pero hay camino.
   - **Algoritmo 130**: el único enlace que queda hacia r5 es ROJO, y está podado. **No hay camino.**

   Se comportan distinto porque la **restricción** solo se nota cuando el camino preferido desaparece. Con todo sano, dos algoritmos pueden dar el mismo camino; ante fallos, uno degrada (128: "lo más rápido que quede") y el otro prefiere no dar servicio a romper su regla (130: "nunca por terceros").

**9.**

1. Gana la FAD de **r5**, porque tiene **mayor prioridad** (200 > 100). **Todos** los routers, incluido r1, calculan el algoritmo 128 con **coste IGP**. Camino: **r1 → r2 → r5** (coste 20, 22 ms). El algoritmo de "baja latencia" ya no lo es, y la VRF VOZ va por el camino lento.
2. A igual prioridad, gana el router con el **System ID más alto**: r5 (`0000.0000.0005`) frente a r1 (`0000.0000.0001`). El resultado sería el mismo.
3. Una FAD mal configurada en **un solo router** cambia el significado del algoritmo **en toda la red**. En operación: anuncia las FAD solo desde unos pocos routers designados (dos, por redundancia), con la misma definición y una prioridad clara; y vigila con `show` qué FAD está elegida, no solo la que tienes configurada localmente.

**10.**

- **Lista explícita de 2 SIDs con `H.Encaps`**: cabecera IPv6 exterior (40) + SRH (8 fijos + 2 × 16) = **80 bytes**.
- **Flex-Algo**: el camino va implícito en el locator, así que basta con **un SID**, el de servicio de r5. Con `H.Encaps.Red`, solo la cabecera exterior: **40 bytes**. Con `H.Encaps` normal, 40 + 8 + 16 = 64 bytes.

Además de ahorrar cabecera, con Flex-Algo **no hay política que mantener**: si la red cambia, el IGP recalcula el camino del algoritmo 128 solo.

**11.** Sin el enlace r1–r2, en el algoritmo 129 (sin ROJO, coste IGP):

- r1 → r3 → r4 → r5 = 20 + 20 + 20 = **60**

El camino post-convergencia es **r1 → r3 → r4 → r5**. El respaldo **no** puede usar el enlace r2–r5, ni siquiera durante los milisegundos de la reparación: el respaldo de un algoritmo se calcula **dentro de ese algoritmo**, respetando su métrica y sus restricciones. Si no, el fallo de un enlace rompería la promesa del algoritmo justo cuando más importa. Los SIDs de la lista de reparación saldrían del bloque del algoritmo 129, **`5f00:81::/32`**. (Aquí, además, no haría falta lista de reparación: r3 alcanza r5 sin volver por r1, así que basta con reenviar por r3.)

**12.**

1. **Falsa.** Flex-Algo **se añade** al algoritmo 0, que sigue calculándose para el tráfico normal.
2. **Verdadera.** Es la forma en que SRv6 sabe por qué algoritmo reenviar: el locator del destino.
3. **Falsa.** Si no hay camino en un algoritmo, el destino es inalcanzable **en ese algoritmo**; no hay vuelta atrás automática al 0.
4. **Falsa.** Flex-Algo separa caminos **lógicamente**, pero no reserva recursos. Para eso hacen falta QoS o particiones de recursos (*hard slicing*).
5. **Verdadera.** Basta con que el destino exterior sea un SID del locator del algoritmo 128, y con `H.Encaps.Red` no hay SRH.
6. **Falsa.** Basta con que la anuncien unos pocos routers (se recomiendan dos). Lo que sí tienen que hacer todos los que quieran usarlo es **participar** en el algoritmo.

**Reto de diseño.** Una propuesta:

- **Algoritmo 130**: métrica de **retardo** y *exclude-any* **ROJO** (como en el ejercicio 8).
- **Locators**: bloque **`5f00:82::/32`** (`0x82` = 130), con `5f00:82:N::/48` en cada router. Todos los routers por los que deba pasar este tráfico tienen que **participar** en el 130.
- **Servicio**: en el PE de destino, la VRF del cliente asigna su SID `End.DT4` (o `End.DT6` / `End.DT46`) desde el locator `5f00:82:N::/48`. BGP lo anuncia como siempre, y el tráfico sigue el camino del algoritmo 130 sin políticas en el origen.
- **Y no olvides el ejercicio 6**: comprueba que el algoritmo 130 tiene caminos redundantes **dentro de su topología podada** hasta cada PE. En esta red, la caída de r4–r5 deja al 130 sin camino a r5 (ejercicio 8), así que haría falta un segundo enlace sin ROJO y de baja latencia hacia r5.
