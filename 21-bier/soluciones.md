# 21 · Soluciones

Vuelve a la [práctica](practica.md) o a la [teoría](README.md).

## Parte A

**A1.** El bit *k* es el bit *k − 1* contando desde la derecha (el bit 1 es el de más a la derecha).

- {3, 6}: `0010 0100` = **0x24**.
- {1, 2, 64}: `1000 … 0000 0011` = **0x8000000000000003**.

**A2.** En r5:

| Vecino | Por | F-BM |
|---|---|---|
| r6 | `eth3` | {6} |
| r2 | `eth1` | {1, 3, 4} |

r1, r3 y r4 se alcanzan por r2. En r1, una sola entrada: vecino r2, por `eth2`, F-BM {3, 4, 5, 6}.

**A3.** **Dos** copias. El bit más bajo es el 4: su entrada es la de r4 (F-BM {4}), así que envía una copia por `eth3` con {4, 6} AND {4} = **{4}**, y apaga el 4. Queda {6}: su entrada es la de r5 (F-BM {5, 6}), así que envía una copia por `eth4` con {6} AND {5, 6} = **{6}**, y apaga el 5 y el 6. No queda nada. Por `eth2` (r3) no sale nada.

**A4.** 1000 / 256 = 3,9, así que hacen falta **4** conjuntos (SI 0 a 3). Con receptores en los 1000 PE, el BFIR envía **4** paquetes, uno por conjunto. Si todos los receptores están en los PE 1 a 200, que caben en el primer conjunto, envía **uno**. Por eso conviene numerar los BFR-id de forma que los PE que suelen recibir lo mismo caigan en el mismo conjunto.

**A5.** En el módulo 20 había que cambiar el **árbol**: quitar la rama hacia r4 en el nodo de replicación (r2), y en una red real lo haría el controlador. Aquí solo cambia el **BitString** que pone el BFIR. r2 y los demás no se enteran, porque no guardan nada del grupo.

## Parte C

**C1.** Coinciden con A2. En r2: {3} por `eth2`, {4} por `eth3` y {5, 6} por `eth4`.

**C2.** Las dos rutas tienen **el mismo siguiente salto**: la link-local de r5, por `eth4`. Por eso r5 y r6 comparten entrada en la BIFT y su F-BM es {5, 6}.

**C3.** Porque r2 no tiene BFR-id: no es ni BFIR ni BFER, solo un BFR de tránsito, y no necesita bit. Para poner un receptor detrás de r2, habría que darle un BFR-id (y una línea en `dominio.txt`). Las BIFT de los demás se recalcularían solas y r2 aparecería en ellas.

## Parte D

**D1.** r2 escribe `3 copias · eth2 {3} · eth3 {4} · eth4 {5,6}`, y r5 escribe `1 copia · local → 10.0.5.50 · eth3 {6}`. r5 entrega su copia (su bit es el 5) y reenvía lo que queda, {6}, hacia r6.

**D2.**
- Next Header **`fd`** (253): detrás de la IPv6 va la cabecera BIER.
- *Hop Limit* **1**. Las dos direcciones son **link-local** (`fe80::…`): de r2 a r5, de vecino a vecino, como en BIERin6.
- TTL BIER: un valor algo menor que 64 (lo ha restado cada BFR). Proto **4** (IPv4) y BFIR-id **1** (r1).
- BitString: `0000 0000 0000 0030`, es decir, {5, 6}.

**D3.** En r6, el BitString es **`…0020`** ({6}): r5 ha apagado su propio bit y solo ha dejado el de r6. El TTL BIER es uno menos que en D2, porque lo ha restado r5.

## Parte E

**E1.** r1 pone **{3, 5, 6}**: `0x34`. h4 deja de recibir.

**E2.** La BIFT de r2 **no cambia**: sigue siendo {3}, {4} y {5, 6}. La BIFT depende de la topología, no de quién quiere qué grupo. En el módulo 20, quitar un receptor obligaba a cambiar el estado de replicación del nodo que bifurca.

**E3.** r1 pone {3, 6}. r2 envía hacia r5 una copia con {6} ({6} AND {5, 6}). r5 **no** encuentra su bit, así que **no entrega** nada a h5: solo reenvía hacia r6 con {6}. Su registro dice `1 copia · eth3 {6}`, sin `local`. r5 sigue reenviando BIER aunque ya no tenga receptores.

## Parte F

**F1.** Reciben **h3 y h4**. **No** reciben **h5 ni h6**: todo lo que pasa por r5. Las BIFT de r1 y r2 **no cambian**: para IS-IS, r5 está perfectamente, y r2 sigue enviando la copia {5, 6} hacia r5, donde ya nadie la procesa. El IGP no lo arregla porque no sabe nada de BIER: un router que enruta bien pero no reenvía BIER es un agujero negro para el multicast. En una red real, cada BFR anuncia en el IGP que sabe hacer BIER (RFC 8401), y los demás no lo usan como siguiente salto si no lo anuncia.

**F2.** Si cayera el enlace r2–r5, IS-IS lo vería y r2 perdería sus rutas hacia r5 y r6 (en esta red no hay otro camino). En el siguiente cálculo de la BIFT, unos segundos después, la entrada {5, 6} desaparecería. r2 apagaría esos bits al reenviar y lo anotaría en su registro como `sin ruta a {5}`. Si hubiera un camino alternativo, la BIFT lo tomaría sola, sin tocar el BFIR ni ningún árbol.

**F3.** Al arrancar otra vez el script de r5, h5 y h6 vuelven a recibir y `verificar.sh` da todo en verde.
