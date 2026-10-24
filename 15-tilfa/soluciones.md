# 15 · Soluciones

> Las salidas son orientativas; los valores de función de los SIDs (End/End.X) los asigna FRR y variarán.

## Parte A

**A1.** Porque la reconvergencia del IGP tarda (decenas de ms a segundos) y durante ese tiempo el tráfico que iba por el enlace caído **se pierde**. El **fast-reroute** conmuta a un camino de respaldo **ya precalculado e instalado** en cuanto detecta el fallo (típicamente < 50 ms), sin esperar al IGP, evitando esa pérdida.

**A2.** LFA clásico solo funciona si existe un **vecino alternativo** cuyo camino más corto al destino no vuelva por el PLR; en muchas topologías **no existe** (cobertura del 67–99 %, no garantizada). **TI-LFA** usa una **lista de SIDs** para forzar la ruta post-convergencia, así que **no depende** de que haya un vecino limpio: da **cobertura garantizada** en cualquier red con doble conexión.

**A3.**
- **P-space**: routers que el PLR alcanza por sus caminos más cortos **sin pasar** por el recurso protegido (el *extended* añade los alcanzables vía otros vecinos del PLR).
- **Q-space**: routers cuyo camino más corto **al destino** no pasa por el recurso protegido.
- **Nodo PQ**: uno que está en ambos. Si existe, la repair list es de **un solo segmento** (hacia el nodo PQ).

**A4.** En protección de **enlace** se quita de la topología solo el **enlace** que falla (el respaldo puede pasar aún por el vecino). En protección de **nodo** se quita el **vecino entero y todos sus enlaces** (por si lo que falla es el nodo); puede requerir un SID más y nunca usa ese vecino.

**A5.** Porque las L3VPN viajan **encapsuladas sobre el transporte**: el paquete exterior va hacia el locator del PE de destino, y esa ruta (al locator) es una ruta IS-IS. Si TI-LFA protege las rutas a los locators, cualquier servicio que las use (L3VPN, TE) hereda la protección **sin configurar nada por-servicio**: se protege el transporte y el resto va encima.

## Parte B

### B1
1. `fast-reroute summary` muestra los prefijos con protección (los locators/loopbacks alcanzables); debería haber cobertura para r4 por el camino alternativo.
2. Para `3fff:0:ff::4`: nexthop **primario** = por **r2** (`eth2`, coste 20); nexthop de **respaldo** = por **r3** (`eth3`). Coinciden con "primario por r2" y "respaldo por r3".

### B2
1. Sin fallo, el tráfico pasa por **r2** (el camino más corto): la captura de r2 lo ve, la de r3 no.

### B3
1. El ping **se recupera**: se pierden unos pocos paquetes (los del intervalo de detección/conmutación) y luego sigue.
2. Tras tirar r1–r2, el tráfico pasa por **r3** (la captura de r3 lo ve; r2 ya no existe para ese camino).
3. (Al reparar `eth2`, el tráfico vuelve al primario por r2.)

### B4
1. En este diamante simple, la cobertura probablemente no cambia: el respaldo por r3 ya evita a r2 por completo (r3 es un camino disjunto). La protección de **nodo** importaría si r2 tuviera **más vecinos** y hubiera destinos alcanzables solo "a través" de r2: entonces el respaldo tendría que evitar **todo** r2 (no solo el enlace r1–r2), y podría necesitar un SID adicional para rodear el nodo.

### Reto
1. En un **anillo de 5 nodos** (r1–r2–r3–r4–r5–r1), si r1 protege su enlace hacia r2 para llegar a, digamos, r3: el otro vecino de r1 es r5, y el camino más corto de r5 a r3 podría **volver** por r1 (r5→r1→r2→r3) → sería un **bucle**, así que r5 **no** es un LFA válido. LFA clásico no cubre ese caso.
2. TI-LFA construiría una repair list que empuje el tráfico por el anillo "al revés" hasta un punto desde el que el camino al destino ya no vuelva por el enlace caído: por ejemplo `<Node-SID(r5), ...>` y, si hace falta, un `Adj-SID` para forzar el salto r5→r4, hasta alcanzar un **nodo PQ** (uno que r1 alcance sin cruzar r1–r2 y cuyo camino a r3 tampoco lo cruce). Si ese PQ existe, basta su único SID.
3. Porque TI-LFA elige como respaldo **exactamente la ruta que el IGP usará tras reconverger** (la post-convergencia). Así, cuando el IGP termina de recalcular y actualiza las rutas, el camino no cambia → no hay un periodo intermedio con rutas inconsistentes entre routers (micro-bucles); el tráfico ya iba por donde acabará yendo.
