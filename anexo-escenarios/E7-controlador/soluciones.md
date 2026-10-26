# E7 · Soluciones

Vuelve a la [práctica](practica.md) o al [escenario](README.md).

## Parte A

**A1.** Porque en un dominio IS-IS de un solo nivel **todos los routers tienen la misma base de datos**: cada uno recibe las LSP de todos los demás. Exportarla desde uno o desde todos da la misma información. Si r2 se cayera, la sesión BGP-LS caería con él, ctl borraría lo aprendido y el controlador se quedaría sin topología (la parte F). En producción se configuran **dos productores** (o más), en sitios distintos, y el controlador fusiona lo que recibe de ambos.

**A2.** Con 6 ms en r3–r5, el camino de abajo pasa a costar 10 ms. El de menor retardo es **r1 → r2 → r5 → r6** (2 + 3 + 2 = 7 ms). Segmentos: desde r1, el camino más corto hacia r2 es el enlace directo, pero hacia r5 no pasa por r2 (r1 → r3 → r5, coste 25, es más corto). Desde r2, el camino más corto hacia r5 tampoco es el enlace directo: r2 → r3 → r5 (20) gana a r2 → r5 (25). Así que hace falta el **`End.X` de r2 hacia r5**, que además lleva el paquete hasta r2, y después el SID de r6, porque desde r5 el camino más corto a r6 es el enlace directo. Lista: `End.X(r2→r5)`, `SID de ORO de r6`.

**A3.** Porque con dos caminos de coste mínimo, el router reparte el tráfico entre los dos (ECMP), y el paquete puede ir por el que **no** queremos. Un `End` dice "ve hasta este nodo por el camino más corto", y si hay varios, no controla cuál. Para fijar uno solo hace falta un segmento que los distinga: el `End` de un nodo intermedio que solo esté en uno de ellos o, si no lo hay, el `End.X` del enlace.

**A4.** **Dejarlas**: el tráfico sigue por caminos que eran buenos hace un momento y, si la red no ha cambiado, siguen siéndolo. Pero si la red cambia mientras tanto, nadie lo corrige (la parte F lo muestra). **Quitarlas**: el tráfico vuelve al camino del IGP, que siempre es válido aunque no cumpla el SLA. Pero un fallo del controlador provoca un cambio en toda la red. Los controladores reales suelen **dejarlas** (la red no depende del controlador para funcionar) y confían en el camino de respaldo de cada política y en la protección local.

## Parte C

**C1.** **6** de tipo `node` (una por router), **20** de tipo `link` (10 enlaces, una NLRI por **cada sentido**, porque cada router anuncia sus propias adyacencias con sus propios atributos: la métrica o el retardo de ida y de vuelta podrían ser distintos), varias de tipo `ipv6Prefix` (loopbacks, redes de enlace y locators) y al menos **6** de tipo `srv6Sid` (los `End` de cada nodo). Los `End.X` no tienen NLRI propia: van como atributo de la NLRI de su enlace.

**C2.** El enlace r2 → r5 tiene `igpMetric` **25**, `delay` **3000** (µs) y, en `srv6EndxSids`, un `End.X` del locator de r2 (`5f00:0:2:…`). Coincide con el `End.X` que r2 tiene en su kernel con salida por `eth4`, el enlace hacia r5.

**C3.** ctl **no tiene** ninguna ruta hacia la red (solo la de su enlace con r2) y **no participa** en IS-IS. No le hace falta: para conocer la topología le basta la sesión BGP con r2, que es directa. Un controlador está fuera del plano de datos.

**C4.** ORO va por **r1 → r3 → r5 → r6** (6 ms), aunque IS-IS elegiría r1 → r2 → r4 → r6 (coste 30, pero 9 ms). PLATA va por **r1 → r2 → r4 → r6**, igual que IS-IS. ORO lleva **dos** segmentos: el `End` de r5 (de r1 a r5, el camino más corto ya pasa por r3) y el SID de r6. PLATA lleva **uno**, el SID de r6, porque su camino es el del IGP.

## Parte D

**D1.** El siguiente salto de cada estática es la dirección del primer vecino del camino: `3fff:0:13::3` (r3) para ORO y `3fff:0:12::2` (r2) para PLATA. Pero **no es eso lo que decide el camino**: el kernel enruta el paquete ya encapsulado por su destino exterior, el primer segmento. ORO sale por `eth2` porque su primer segmento es el `End` de r5, y el camino más corto de r1 a r5 pasa por r3. Si la lista de ORO fuera solo el SID de r6, el paquete saldría por `eth1` (hacia r2), aunque la estática diga r3. Es justo el error que tenía la primera versión de este controlador (README, sección 3).

**D2.** Unos pocos segundos: lo que tarda IS-IS en detectar la caída y regenerar sus LSP, más lo que tarda BGP-LS en retirar las NLRI, más hasta 5 s del bucle. Cambian los **cuatro** servicios. PLATA cambia porque su restricción es "no usar enlaces de ORO", y ORO ahora usa r1–r2 y r2–r5: el camino anterior de PLATA (r1 → r2 → r4 → r6) comparte r1–r2 con él.

**D3.** En r2 `eth1` el destino es el **`End.X` de r2 hacia r5** (`5f00:0:2:…`), con una SRH de dos segmentos. En r5 `eth4` el destino ya es el **SID de ORO de r6**: lo ha cambiado r2 al ejecutar su `End.X`. Hace falta el `End.X` porque desde r2 hay dos caminos de coste 25 hasta r5 (el directo y r2 → r4 → r5), y con el `End` de r5 el tráfico podría ir por r4.

**D4.** El enlace vuelve a aparecer en BGP-LS (20 NLRI de enlace) y el bucle reprograma los cuatro servicios como al principio.

## Parte E

**E1.** ORO va por **r1 → r2 → r4 → r6** (el camino IGP, 9 ms de retardo) y PLATA, que tiene que evitarlo, por **r1 → r3 → r5 → r6**. Los dos con un solo segmento. Con el objetivo equivocado, el controlador manda a ORO por el camino de más retardo, aunque haya uno mejor.

**E2.** En el JSON de ctl, el enlace r2 → r4 pasa a `delay: 1000`. Con 1 ms, el camino de arriba cuesta 2 + 1 + 2 = 5 ms, menos que el de abajo (6 ms). ORO pasa a ir por **r1 → r2 → r4 → r6**, y PLATA, que no puede tocarlo, por **r1 → r3 → r5 → r6**. Nadie ha tocado el controlador: el cambio ha llegado solo por IS-IS y BGP-LS.

**E3.** Una forma: que `evitar` sea una lista que admita nombres de servicio y enlaces concretos.

```python
{'nombre': 'PLATA especial', 'vrf': 'PLATA', 'de': 'r1', 'a': 'r6', 'prefijo': '192.168.120.0/24',
 'objetivo': 'igp', 'evitar': ['ORO ida', ('r2', 'r4')]},
```

Y en `ciclo`, construir los prohibidos así:

```python
prohibidos = set()
for x in s.get('evitar', []) if isinstance(s.get('evitar'), list) else [s.get('evitar')]:
    prohibidos |= usados.get(x, set()) if isinstance(x, str) else {frozenset(x)}
```

(Ojo: el prefijo `192.168.120.0/24` ya lo usa "PLATA ida"; para probarlo, quita o comenta ese servicio, o usa otra sede.)

**E4.** En `segmentos`, basta con devolver `[end[n] for n in c[1:-1]] + [sid_servicio]`: el `End` de cada nodo intermedio. Para ORO (r1 → r3 → r5 → r6) serían el `End` de r3, el de r5 y el SID de r6: 3 segmentos en lugar de 2, es decir, **16 bytes más** por paquete. Para PLATA, 3 en lugar de 1: **32 bytes más**, y una SRH que antes no hacía falta tan larga. Y en caminos largos, la diferencia crece con cada nodo.

## Parte F

**F1.** El controlador dice que **ctl no tiene topología** y termina sin tocar nada. Las estáticas que programó antes **siguen** en r1 y r6: el controlador no las quita al perder la vista de la red.

**F2.** ORO **sigue funcionando**: su lista solo nombra a r5 y el SID de r6, y el IGP encuentra otro camino hasta r5. Pero desde r1 hay dos de igual coste (r1 → r2 → r5 y r1 → r2 → r4 → r5, los dos de 35), y el reparto por ECMP decide cuál usa cada flujo. Por el primero ORO tarda 2 + 3 + 2 = 7 ms, y por el segundo 2 + 5 + 1 + 2 = **10 ms**. Nadie elige el mejor, y nadie se entera: la promesa a ORO se rompe en silencio. Que funcione es mérito de la lista mínima: una lista que fijara cada enlace con `End.X` dejaría de funcionar del todo.

**F3.** Al quitar el `shutdown`, la sesión vuelve, ctl recibe otra vez la topología y el controlador reprograma ORO por r2 y r5. Al levantar el enlace y ejecutar `verificar.sh`, todo vuelve a estar en verde.
