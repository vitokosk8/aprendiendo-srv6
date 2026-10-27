# 19 · Soluciones

Vuelve a la [práctica](practica.md) o a la [teoría](README.md).

## Parte A

**A1.** Con replicación en el ingreso: 40 canales × 8 Mb/s × 30 hojas = **9,6 Gb/s**, más la cabecera IPv6 de cada copia. Es casi todo el enlace de 10 Gb/s, sin margen para nada más. Con un árbol, por ese enlace saldría **una** copia de cada canal: 40 × 8 = **320 Mb/s**. No cabe de forma razonable: este es el caso típico en el que la replicación en el ingreso no sirve.

**A2.** Con replicación en el ingreso, **ninguna**: el P solo ve paquetes unicast hacia SIDs, y solo necesita sus rutas de IS-IS. Con PIM, **40** entradas (S, G), una por canal, en cada router por el que pase el árbol. Y cada una con sus temporizadores y sus mensajes de PIM periódicos.

**A3.** Es multicast **en las dos puntas**: de h1 a r1 (la fuente envía al grupo) y de r3 a h3 (el receptor recibe del grupo). Entre r1 y r3 es **unicast**: un paquete IPv6 normal hacia el SID de r3. El paquete multicast viaja **dentro**, sin cambios salvo el TTL.

**A4.** Cada PE anuncia una ruta EVPN de **tipo 3** (*Inclusive Multicast Ethernet Tag*) por cada instancia de servicio, diciendo "para el tráfico BUM de esta instancia, envíamelo aquí". Con SRv6, ese "aquí" es su SID **`End.DT2M`**: el behavior que desencapsula una trama y la inunda por las interfaces de la instancia (escenario E3). El PE de entrada, al recibir tráfico BUM, envía una copia a cada uno de los 19 PE restantes.

## Parte C

**C1.** **Tres** copias, hacia r3, r4 y r5: el registro dice `10.0.1.10 → 233.252.0.1: 3 copias (r3 r4 r5)`. Los tres receptores tienen `hola` en `/tmp/recibido.txt`.

**C2.** **Tres** paquetes por cada datagrama. Lo único que cambia entre ellos es el **destino IPv6**: `5f00:0:3:d4::`, `5f00:0:4:d4::` y `5f00:0:5:d4::`. **No llevan SRH**: la cabecera IPv6 tiene *Next Header* 4 y detrás va directamente el paquete IPv4. Es el encapsulado reducido con un solo SID (módulo 09).

**C3.** En r3 `eth1`, **uno**: la copia para r3. Las otras dos salen de r2 por otros enlaces. Entre r3 y h3 el paquete ya es **IPv4 normal**, con destino `233.252.0.1`, origen `10.0.1.10` y el TTL dos unidades más bajo que al salir de h1 (lo restan el replicador y r3).

**C4.** **No**: `End.DX4` envía el paquete directamente al siguiente salto configurado (`nh4 10.0.3.30`, h3), sin mirar su destino. Si hubiera dos receptores en la sede, solo uno lo recibiría. Para entregarlo a todos, la hoja tendría que pasar el paquete a su enrutamiento multicast (con IGMP en la sede, como haría un PE real) o usar un `End.DX4` hacia un switch y enviarlo como multicast de capa 2.

**C5.** El TTL se resta en `cab[8] -= 1` (y se rehace el checksum de la cabecera). La cabecera IPv6 **no la escribe el script**: el socket `AF_INET6, SOCK_RAW, IPPROTO_IPIP` hace que el kernel ponga delante de cada envío una cabecera IPv6 con *Next Header* 4, con el destino de `sendto()` y el origen que corresponda según la ruta. El script solo entrega el paquete IPv4 que hay que llevar dentro.

## Parte D

**D1.** El registro dice primero `hojas: r3=… r4=…` (ha releído el fichero) y después `2 copias (r3 r4)`. h5 no recibe nada nuevo.

**D2.** **No** hace falta reiniciarlo: relee `hojas.txt` cada vez que cambia. En una red real, el cambio lo provocaría el **receptor**: deja el grupo con IGMP, r5 ve que ya no le queda ninguno y **retira** su ruta BGP (*Leaf A-D* en MVPN o la de tipo 3 en EVPN). El PE de entrada, al ver la retirada, deja de replicar hacia r5.

**D3.** El envío hacia `5f00:0:6:d4::` falla **en el propio r1**: no tiene ninguna ruta hacia `5f00:0:6::/48`, porque ningún router anuncia ese locator. El registro muestra un ⚠️ con el error (*Network is unreachable*) y sigue diciendo `3 copias (r3 r4 r5)`. **Las demás copias no se ven afectadas**: cada una es un paquete independiente.

## Parte E

**E1.** En r1 `eth2` sale aproximadamente el **triple** de bytes que en r2 `eth2`: tres copias frente a una. Cada copia lleva el paquete de h1 (1000 bytes de datos + 8 de UDP + 20 de IPv4) más **40 bytes** de la cabecera IPv6 exterior, sin SRH. (Los contadores incluyen también la cabecera Ethernet y algo de tráfico de IS-IS, así que la cuenta no sale exacta.)

**E2.** Con una sola hoja, el enlace r1–r2 lleva **una** copia por datagrama: los mismos bytes que el enlace hacia esa hoja. El ancho de banda de la replicación en el ingreso crece **linealmente con el número de hojas**.

## Parte F

**F1.** h4 **no recibe** el datagrama. El registro del replicador sigue diciendo `3 copias (r3 r4 r5)`: para él, todo va bien. La copia llega hasta r4 (la ves en la captura de r4 `eth1`, con destino `5f00:0:4:d5::`), porque cualquier dirección de `5f00:0:4::/48` se enruta hacia r4. Pero r4 no tiene ningún SID con ese valor, y la descarta.

**F2.** `ip -6 route show | grep seg6local` en r4 muestra su `End.DX4` en `5f00:0:4:d4::`, no en `d5`. Es el error típico de una lista de hojas mal mantenida: el PE de entrada envía, el núcleo entrega, y la hoja descarta en silencio. Por eso, en producción, el SID **lo anuncia la propia hoja** por BGP en lugar de configurarse a mano en el PE de entrada. Al corregir el SID en `hojas.txt`, h4 vuelve a recibir y `verificar.sh` da todo en verde.
