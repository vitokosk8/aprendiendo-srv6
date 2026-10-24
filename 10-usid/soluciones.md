# 10 · Soluciones

> Las salidas de comandos son orientativas y se ajustarán con las de una ejecución real del laboratorio.

## Parte A

**A1.** `(128 − 32) / 16 = 96 / 16 = 6` uSID. En formato F3216 caben **6 uSID** en una sola dirección IPv6 (uno en la posición activa tras el bloque y cinco en el argumento).

**A2.** Camino de 5 saltos de tránsito:
- **SRv6 clásico**: 5 SID × 16 bytes = **80 bytes** de lista, **más** los 8 de la cabecera SRH → necesita **SRH**.
- **uSID**: 5 × 2 bytes = **10 bytes**, que caben **dentro de la dirección de destino** → **no hace falta SRH** (5 ≤ 6). 
- Diferencia enorme: de 88 bytes de SRH a 0.

**A3.** Contenedor `5f00:0:2:3::` = `5f00:0000:0002:0003:0000:0000:0000:0000`:
- **Bloque** (32 bits): `5f00:0000` (`5f00:0`).
- **uSID activo** (16 bits tras el bloque): `0002` → el uSID de **r2**.
- **Argumento** (resto): `0003:0000:0000:0000:0000` (contiene el `0003` de r3 y ceros).
- El paquete se dirige **ahora mismo a r2**.

**A4.** El **shift-and-continue** de uN:
- Si el **argumento no es cero** (quedan uSID): el router **desplaza** el argumento 16 bits hacia la izquierda (el siguiente uSID pasa a la posición activa), rellena con ceros por la derecha, y reenvía al nuevo destino.
- Si el **argumento es cero**: no quedan más uSID en el contenedor; se acabó. El router toma el siguiente segmento (de una SRH, si la hay) o aplica el comportamiento final.

**A5.** Tras r2, el `0002` se consume y el `0003` pasa a la posición activa: el nuevo destino es **`5f00:0:3::`** (`5f00:0000:0003:0000:...`).

**A6.** Porque el uN se instala en el **`/48`** = bloque + uSID de nodo, y esa única entrada hace *match* con **cualquier** contenedor que tenga ese uSID activo, **sin importar el resto del argumento** (los demás saltos). Un router no necesita una entrada por cada camino posible: con **una ruta por nodo** procesa infinitos contenedores. Ventaja operativa: las **tablas de reenvío se mantienen pequeñas y estables** aunque se definan miles de políticas de ingeniería de tráfico (al contrario que en MPLS, donde cada LSP consume etiquetas y estado).

## Parte B

### B1

1. La ruta uN se ve algo así:
   ```
   5f00:0:2::/48  encap seg6local action End flavors next-csid lblen 32 nflen 16 dev eth1 ...
   ```
   Con `action End`, `flavors next-csid`, `lblen 32` y `nflen 16`.
2. Es un **`/48`** (bloque de 32 + uSID de nodo de 16). Procesa **todos** los contenedores que lleguen con el uSID `0002` activo, sea cual sea el argumento (`5f00:0:2:3::`, `5f00:0:2:5:9::`, etc.). Una sola entrada, muchos caminos.

### B2

1. En **eth1** (r1→r2): destino = **`5f00:0:2:3::`** (el contenedor completo, uSID activo `0002`).
2. En **eth2** (r2→r3): destino = **`5f00:0:3::`** (ha cambiado). El `0002` se consumió y el `0003` pasó a la posición activa.
3. r2 ejecutó su **uN**: consumió su uSID (`0002`) y **desplazó** el argumento, de modo que el uSID de r3 (`0003`) quedó activo. Todo en la **dirección de destino**, sin tocar ninguna lista de segmentos.
4. En el **tránsito** no hay SRH para los saltos: los saltos van comprimidos en el destino. (Sí hay una pequeña SRH de 1 entrada con el *service SID* final; ver B3.)

### B3

1. El tránsito (`[r2, r3]`) no gasta SRH: va en la dirección. El **service SID** final (`5f00:0:3:dc04::`) sí viaja en una SRH de **1 entrada** (16 bytes + 8 de cabecera), porque en este lab la entrega se hace con un SID clásico. Frente al módulo 09 (donde los dos saltos eran dos... en realidad 1 SID en SRH + 1 en destino), aquí los **dos saltos de tránsito** no ocupan SRH: solo el service SID.
2. Las dos partes en la captura:
   - **Destino IPv6 exterior** = contenedor con los uSID de tránsito (`5f00:0:2:3::`).
   - **SRH** (si aparece) = una sola entrada con el service SID (`5f00:0:3:dc04::`).

### B4

1. **Sí funciona**, sin tocar r2. La ruta uN `/48` de r2 ya procesaba cualquier contenedor con `0002` activo; el nuevo contenedor (`5f00:0:2:3::`) también lo tiene, así que r2 lo desplaza igual. Es justo la ventaja de "una ruta por nodo".
2. El service SID ahora es `5f00:0:3:d600::` = **End.DT6**: r3 desencapsula el paquete y busca el **IPv6 interior** (`3fff:0:2::20`) en la tabla, entregándolo a h2.
3. (Se limpia con `ip -6 route del 3fff:0:2::20/128`.)

### B5

1. uSID activo = `0002`; argumento = `0003:0000:0000:0000:0000`.
2. Shift: el argumento se desplaza 16 bits a la izquierda tras el bloque → activo `0003`, argumento todo a cero:
   ```
   5f00:0000:0003:0000:0000:0000:0000:0000  =  5f00:0:3::
   ```
   Coincide con el destino que viste en el tramo r2→r3 en B2.

### Reto: un contenedor de 3 saltos

1. Contenedor `5f00:0:2:3:9::` = `5f00:0000:0002:0003:0009:0000:...`:
   - En r1→r2: activo `0002` (r2). r2 desplaza → `5f00:0:3:9::` (activo `0003`).
   - En r2→r3: activo `0003` (r3). r3 desplaza → `5f00:0:9::` (activo `0009`).
   - El paquete iría ahora hacia quien posea el uSID `0009`; como es ficticio y nadie lo anuncia, se descartaría. Lo importante: **tres saltos cabían en una dirección**, desplazándose uno a uno.
2. Según la versión. Un iproute2 reciente muestra `next-csid` en la ayuda de `seg6local`. El soporte de micro-desencapsulado (uDT/uDX) como flavor depende del kernel/iproute2; si aparece, podrías meter el service SID como uSID en el mismo contenedor y quitar la última SRH.
3. Con 6 saltos: en **uSID**, **una sola dirección** (los 6 caben en F3216), **cero SRH**. En **SRv6 clásico**, 6 SID × 16 = 96 bytes de lista **más** la SRH. uSID es la razón por la que caminos largos de TE son viables en el núcleo sin inflar cada paquete.
