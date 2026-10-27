# 20 · Soluciones

Vuelve a la [práctica](practica.md) o a la [teoría](README.md).

## Parte A

**A1.**

```
R:  rama A <Replication-SID de A>
    rama B <Replication-SID de B>
A:  rama H1 … rama H4   (cada una con el Replication-SID de la hoja)
B:  rama H5 … rama H8
```

De R salen **2** copias (una hacia A y otra hacia B). Con replicación en el ingreso saldrían **8**, una por hoja.

**A2.** Es un nodo ***bud***: hoja y nodo de replicación a la vez. Con cada paquete hace las dos cosas: envía una copia por cada rama (H5–H8) y **entrega** otra en local, quitando la cabecera exterior y procesando el paquete interior.

**A3.** Porque un solo paquete de la raíz se convierte en muchos dentro del árbol. Si el *Hop Limit* se agotara en las ramas, cada copia generaría un error, y todos irían hacia el mismo origen: una avalancha de errores provocada por un único paquete. Por eso el RFC 9524 prohíbe el *Time Exceeded* en `End.Replicate` (y el RFC 4443 limita los errores ICMPv6 para tráfico multicast). La consecuencia práctica es que no se puede hacer `traceroute` a través de un árbol.

**A4.** Basta con **un** árbol: los tres canales van a las mismas hojas, así que pueden compartirlo. El estado del núcleo no crece con los canales. El problema es el **contexto**: la hoja recibe paquetes de los tres canales por el mismo Replication-SID y tiene que saber a qué servicio pertenece cada uno (por ejemplo, a qué VPN). Se resuelve con un **SID de servicio** que viaja detrás del Replication-SID (en una SRH o en un encapsulado interior) o con un árbol por servicio, donde el propio Replication-SID da el contexto. El RFC 9524 deja la señalización de ese contexto a otros documentos.

## Parte C

**C1.** r1 hace **1** copia (hacia r2) y r2 hace **3** (hacia r3, r4 y r5). En el módulo 19, r1 hacía las tres.

**C2.** En r2 `eth1`: origen `3fff:0:12::1` (r1), destino `5f00:0:2:a1::` y un *Hop Limit* H. En r3 `eth1`: el **mismo origen**, destino `5f00:0:3:a1::` y *Hop Limit* H − 1. Lo que ha cambiado son el **destino** (reescrito por r2) y el *Hop Limit* (restado por r2). No han cambiado el origen ni el paquete interior, que sigue siendo el IPv4 de h1 hacia el grupo.

**C3.** r2 tiene un **`blackhole`** porque el kernel de Linux no sabe ejecutar `End.Replicate`. La ruta descarta en silencio el original, y el script, que lo ha visto antes con `AF_PACKET`, hace la parte de **replicar**. r3 tiene un **`End.DX4`**, que hace la parte de **hoja**: quitar la cabecera exterior y entregar el paquete IPv4 al receptor. En un router con `End.Replicate`, los dos serían el mismo behavior con distinto estado: uno con ramas y el otro con el indicador de hoja.

**C4.**
- Paso 2: `if pkt[7] <= 1: continue`. El byte 7 de la cabecera IPv6 es el *Hop Limit*: si es 1 o menos, se descarta sin avisar.
- Paso 3: `base[7] -= 1`.
- Paso 4: el bucle de `enviar()` con la función `copia(sid)`, que escribe los 16 bytes del Replication-SID de la rama en `c[24:40]`, la dirección de destino.

## Parte D

**D1.** Deja de recibir **h5**. r1 **no se entera**: sigue enviando una copia a r2. El cambio es local a r2, como en un router real: cada nodo solo conoce sus ramas.

**D2.** Salen **2** copias de r1: una hacia r2 (que replica a r3 y r4… y también a r5, si no quitaste su rama en D1) y otra directa hacia `5f00:0:5:a1::`. La copia de r5 pasa por r2, pero **como tránsito**: va hacia el locator de r5 y r2 la reenvía sin replicarla. Es una mezcla de árbol y replicación en el ingreso. La raíz puede tener ramas hacia cualquier nodo, sea o no vecino, y las que no son vecinas se recorren con SRv6 unicast. Si dejaste la rama r5 también en r2, h5 recibe **dos** copias de cada datagrama: un árbol mal construido duplica tráfico.

## Parte E

**E1.** Ahora los dos enlaces llevan aproximadamente **los mismos** bytes: una copia por datagrama en cada uno. En el módulo 19, el enlace r1–r2 llevaba el triple. Es la eficiencia del árbol: una copia por enlace.

## Parte F

**F1.** **Nadie** recibe el datagrama. r1 sigue enviando su copia, y llega a r2 (la ves en la captura de `eth1`), pero el kernel de r2 la descarta en su `blackhole` y ya no hay nadie que la replique. Todo lo que cuelga de r2 se queda sin tráfico, aunque r2 siga enrutando unicast con normalidad y el IGP no note nada.

**F2.** En el módulo 19, r2 era un P sin estado multicast: si "se colgara" solo su parte de multicast, no pasaría nada, porque no tenía ninguna. Si se cayera del todo, IS-IS buscaría otro camino (si lo hubiera) y las copias unicast de r1 lo seguirían. Con un árbol, r2 **tiene estado**, y su fallo corta el árbol hasta que el controlador lo recalcule. Si se cayera r1, en los dos casos se perdería todo: es la raíz, donde entra el tráfico. Es el precio del árbol: los nodos que bifurcan son puntos de fallo con estado, y en producción hay que protegerlos o recalcular deprisa.

**F3.** Al arrancar otra vez el script en r2, h3, h4 y h5 vuelven a recibir y `verificar.sh` da todo en verde.
