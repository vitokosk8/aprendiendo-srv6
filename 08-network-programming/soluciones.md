# 08 · Soluciones

> Las salidas de comandos son orientativas y se ajustarán con las de una ejecución real del laboratorio.

## Parte A

**A1.**
- **End**: decrementa Segments Left, copia el siguiente SID al destino y reenvía por la ruta del IGP.
- **End.X**: igual que End, pero reenvía por una **adyacencia (enlace/vecino) concreta**, no por la del IGP.
- **End.DT4**: desencapsula el paquete SRv6 y busca el destino **IPv4 interior** en una tabla de rutas.
- **End.DX6**: desencapsula y entrega el paquete **IPv6 interior directamente a un vecino**, sin búsqueda.
- **H.Encaps**: en el headend, **encapsula** el paquete del cliente dentro de SRv6 y le pone la lista de SID.

**A2.** Las dos desencapsulan en el nodo final, pero:
- **End.DT6** hace una **búsqueda** del destino IPv6 interior en una tabla de rutas. Se usa cuando detrás del PE hay una **red** (varios destinos).
- **End.DX6** hace *cross-connect* **directo** a un vecino fijo, **sin búsqueda**. Se usa cuando el SID representa "este cliente en esta interfaz" (un único destino), y es un poco más rápido.

**A3.** Lista de segmentos (orden del camino): `[SID-End.X-de-r2, SID-End.DT6-de-r3]`. El SID de r2 sería un **End.X** con next-hop la link-local de r3 (fuerza el enlace r2→r3). El SID de r3 sería un **End.DT6** (o End.DX6) para entregar a h2. Con End.X describes el camino **enlace por enlace**; con End dejarías la elección al IGP.

**A4.** Ping de `10.0.1.10` a `10.0.2.20`:
1. **r1 — H.Encaps**: recibe el IPv4, le añade cabecera IPv6 exterior + SRH con `[5f00:0:2:e000::, 5f00:0:3:d400::]` (destino exterior = SID de r2, SL=1) y lo manda al núcleo. El IPv4 queda **dentro**, intacto.
2. **r2 — End**: resta 1 a SL (1→0), copia `5f00:0:3:d400::` al destino exterior y reenvía hacia r3. No mira el IPv4 interior.
3. **r3 — End.DT4**: con SL=0, desencapsula (quita IPv6 exterior + SRH), se queda con el IPv4 interior y busca `10.0.2.20` en la tabla 254 → lo entrega a h2 por la red conectada.

**A5.** `End.DT4` (y End.DT46) usan `vrftable` por razones históricas: se diseñaron pensando en VRF. El número es el **identificador de la tabla de rutas** donde buscar el destino interior. En una VPN real, cada cliente tiene su propia tabla (VRF): un SID `End.DT4 vrftable 10` entrega en la VPN del cliente 10 y otro `vrftable 20` en la del 20, aunque las dos usen las mismas IPv4 privadas. El SID codifica **en qué VPN** entregar.

## Parte B

### B1

1. r2: `5f00:0:2:e000:: ... action End`. r3: `5f00:0:3:d400:: ... action End.DT4` y `5f00:0:3:d600:: ... action End.DT6`. (r1 tiene los suyos para el tráfico de vuelta.)
2. En r1, la ruta de encap se ve así:

   ```
   10.0.2.0/24  encap seg6 mode encap segs 2 [ 5f00:0:2:e000:: 5f00:0:3:d400:: ] dev eth2 ...
   ```

   Lleva la lista de 2 segmentos: primero el End de r2, luego el End.DT4 de r3.

### B2

1. La cabecera exterior va de `3fff:0:ff::1` (el `tunsrc` de r1) a `5f00:0:2:e000::` (SID de r2). La SRH tiene `segleft=1` y la lista `[0]=5f00:0:3:d400::, [1]=5f00:0:2:e000::`.
2. Dentro hay un **paquete IPv4** (de `10.0.1.10` a `10.0.2.20`) con su ICMP. r2 **no lo sabe ni le importa**: solo ve un paquete IPv6 con SRH hacia su SID, ejecuta End y reenvía. El IPv4 es carga opaca.
3. A la salida de r3 hacia h2, el paquete es **IPv4 normal**, sin rastro de SRv6: lo desencapsuló el **End.DT4** de r3.

### B3

1. El End normal (`5f00:0:2:e000::`) reenvía por la ruta del IGP (`action End`). El End.X (`5f00:0:2:e100::`) lleva `action End.X nh6 <LL-r3> dev eth2`: reenvía **obligatoriamente** por ese vecino y esa interfaz, sin consultar el IGP.
2. El ping sigue funcionando: el paquete pasa igual por r2→r3. En esta topología **lineal** no hay diferencia práctica, porque solo hay un camino. La diferencia se notaría si r2 tuviera **dos** caminos hacia r3: con End elegiría el del IGP; con End.X forzarías el enlace que tú quieras, que es la base de la ingeniería de tráfico.
3. —

### B4

1. Tras añadir el `/128`, `ip -6 route get 3fff:0:2::20` muestra la ruta de **encap seg6**, no la del IGP. Gana por **longest-prefix match**: el `/128` es más específico que el `/64` que anuncia IS-IS.
2. Sí, ahora la IPv6 de h2 viaja dentro de SRv6. El SID final es `5f00:0:3:d600::`, el **End.DT6** de r3 (desencapsula y busca el IPv6 interior). En la captura verás la SRH con ese SID en `[0]`.
3. —

### B5

1. Funciona. End.DX6 hace que r3, en vez de **buscar** `3fff:0:2::20` en una tabla (como End.DT6), entregue el paquete **directamente** al vecino `3fff:0:2::20` por `eth2`, sin consultar ninguna ruta. El resultado para h2 es el mismo; cambia lo que hace r3 internamente.
2. Preferirías **End.DX6** cuando el SID representa un **único destino** conocido (un cliente conectado a una interfaz concreta): te ahorras la búsqueda y el estado de una tabla. **End.DT6** cuando detrás hay una **red** con varios destinos, donde sí hace falta buscar.
3. —

### B6

1. El `-s 1400` crea un ICMP de 1400 bytes de datos; el paquete IPv4 interior mide 1400 + 8 (ICMP) + 20 (IPv4) = 1428 bytes. Al encapsularlo, SRv6 añade 40 (IPv6 exterior) + 8 (SRH) + 16×2 (2 SID) = 80 bytes, así que por el núcleo viajan unos **1508 bytes**. Como la MTU del laboratorio es 9500 (containerlab), cabe y funciona.
2. El `-M do -s 1440` pide no fragmentar un paquete de 1440 bytes de datos. Sumando cabeceras y la sobrecarga de SRv6 (80 bytes), el paquete por el núcleo rondaría o superaría la MTU del enlace si esta fuera pequeña; con una MTU muy ajustada, r1 no podría encapsular y enviar sin fragmentar, y avisaría. Es exactamente el problema del módulo 02: **SRv6 añade bytes**, así que las redes SRv6 usan MTU grandes en el núcleo para que el tráfico del cliente quepa con la sobrecarga. (En este laboratorio, con MTU 9500, hace falta un tamaño mayor para forzar el fallo; lo importante es el razonamiento.)

### Reto

El End.DT46 funciona con un solo SID para las dos familias porque, al desencapsular, **mira la versión del paquete interior** (el primer nibble de la cabecera: 4 o 6) y busca en la tabla IPv4 o IPv6 correspondiente. Por eso con un único SID das servicio dual-stack: el nodo decide la familia por el contenido, no por el SID.

```bash
# en r3
ip -6 route add 5f00:0:3:d046::/128 encap seg6local action End.DT46 vrftable 254 dev eth1
# en r1, las dos familias terminan en el mismo SID
ip route    add 10.0.2.0/24    encap seg6 mode encap segs 5f00:0:2:e000::,5f00:0:3:d046:: dev eth2
ip -6 route add 3fff:0:2::20/128 encap seg6 mode encap segs 5f00:0:2:e000::,5f00:0:3:d046:: dev eth2
```

Es lo que se usa en una L3VPN dual-stack real: un SID de servicio por VPN, válido para IPv4 e IPv6. Si tu kernel no soporta `End.DT46`, el comando dará error al añadir la ruta; en ese caso, el equivalente es usar dos SID separados (End.DT4 y End.DT6), como en el resto del laboratorio.
