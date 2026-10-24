# 09 · Soluciones

> Las salidas de comandos son orientativas y se ajustarán con las de una ejecución real del laboratorio.

## Parte A

**A1.** Camino `[S1, S2, S3]`, 3 SID:
- **H.Encaps (completo)**: la SRH lleva los 3 SID → `8 + 16·3 = 56` bytes de SRH.
- **H.Encaps.Red (reducido)**: omite el primer SID (va en el destino), la SRH lleva 2 → `8 + 16·2 = 40` bytes.
- **Ahorro**: 16 bytes (un SID). El reducido siempre ahorra exactamente un SID (16 bytes), sea cual sea la longitud del camino.

**A2.** Porque el **primer SID siempre va en el destino** de la cabecera IPv6 exterior: es la dirección a la que se envía el paquete ahora mismo. Guardarlo además en la SRH es redundante. El reducido lo quita de la SRH y lo deja solo en el destino; cuando el primer nodo ejecuta su `End` y decrementa `Segments Left`, copia el **siguiente** SID (que sí está en la SRH) al destino, y todo sigue igual.

**A3.** Con un solo SID, el reducido no mete ningún SID en la SRH, así que **la SRH se queda vacía y no se pone**. El paquete lleva solo: **IPv6 exterior + el paquete del cliente**. **0 bytes de SRH** (solo los 40 de la IPv6 exterior). Es IPv6-en-IPv6 "normal".

**A4.**
- **PSP** (*Penultimate Segment Pop*): el **penúltimo** nodo quita la SRH al pasar `Segments Left` a 0, antes de reenviar al último.
- **USP** (*Ultimate Segment Pop*): el **último** nodo quita la SRH (agotada, `SL=0`) y sigue procesando.
- **USD** (*Ultimate Segment Decapsulation*): el **último** nodo desencapsula la cabecera exterior + SRH y reenvía el paquete interior.

**A5.** Porque los behaviors de la familia **`End.D*`** (`End.DT4`, `End.DT6`, `End.DX4`, `End.DX6`) **desencapsulan de serie**: llevan el comportamiento USD incorporado por definición. `End.DX4` ya quita la cabecera IPv6 exterior (y la SRH si la hubiera) y entrega el IPv4 interior. El flavor `usd` explícito solo hace falta para que un `End` o `End.X` **normal** (que no desencapsula) pueda, además, desencapsular cuando es el último segmento.

**A6.** Camino `[r2, r3]` con `encap.red` + `PSP`:
```
r1 → r2 :  IPv6 ext [dst=5f00:0:2:e000::] | SRH{ SL=1, [0]=5f00:0:3:dc04:: } | IPv4     ← SÍ hay SRH (1 SID)
r2 → r3 :  IPv6 ext [dst=5f00:0:3:dc04::] | IPv4                                        ← NO hay SRH (PSP la quitó)
```
- En **r1→r2** hay SRH (reducida, con 1 SID).
- En **r2→r3** no hay SRH: r2, con PSP, la quitó al ejecutar su `End`.

## Parte B

### B1

1. La ruta de r1 muestra el modo reducido, algo como:
   ```
   10.0.2.0/24  encap seg6 mode encap.red segs 2 [ 5f00:0:2:e000:: 5f00:0:3:dc04:: ] dev eth2 ...
   ```
   La clave es `mode encap.red` (frente al `mode encap` del módulo 08).
2. El SID de r2 se ve así:
   ```
   5f00:0:2:e000::  encap seg6local action End flavors psp dev eth1 ...
   ```
   El `flavors psp` indica que r2, al ser el penúltimo nodo (su `End` deja `SL=0`), **quitará la SRH** antes de reenviar a r3.

### B2

1. En **eth1** (r1→r2): el paquete lleva **SRH** → Next Header 43 (`ip6[6]==43`); tcpdump lo muestra como `srcrt (len=...)` o `rt6`. Dentro, el IPv4.
2. En **eth2** (r2→r3): **no hay SRH**; el paquete es IPv6 exterior con **Next Header 4** (`ip6[6]==4`), es decir, el IPv4 va directo dentro de la IPv6 exterior. El destino exterior es ya el SID de r3 (`5f00:0:3:dc04::`).
3. r2 ha ejecutado su `End` (pasar al siguiente segmento) y, por el flavor **PSP**, ha **eliminado la SRH** al quedar `Segments Left = 0`. Por eso entra con SRH y sale sin ella. El responsable es **PSP** (Penultimate Segment Pop).

### B3

1. Con `encap` (completo), la SRH lista **2 SID** (`[0]=5f00:0:3:dc04::`, `[1]=5f00:0:2:e000::`); con `encap.red` listaba **1**. El paquete mide **16 bytes más** con el completo.
2. Sí: la diferencia es exactamente un SID = **16 bytes**. Es lo único que cambia entre reducido y completo.
3. (Se vuelve al reducido con el `ip route replace ... mode encap.red`.)

### B4

1. **No aparece ninguna SRH** en ningún tramo: todo es `ip6[6]==4` (IPv4 encapsulado directamente en la IPv6 exterior). Con un solo SID, el reducido no pone SRH.
2. La única sobrecarga de SRv6 son los **40 bytes de la cabecera IPv6 exterior**. Cero bytes de SRH. Es la mínima sobrecarga posible con encapsulado.
3. En este caso r2 **ya no es un segmento del camino** (el único SID es el de r3). r2 simplemente **reenvía por IGP** el paquete IPv6 cuyo destino es el locator de r3; no ejecuta ningún behavior SRv6, así que su flavor PSP **no interviene**. La SRH no existía desde el principio: no hay nada que quitar.

### B5

1. Sin PSP, en **r2→r3** reaparece la **SRH** → Next Header 43 (`ip6[6]==43`), con **`Segments Left = 0`** (ya agotada: el camino está recorrido, pero la SRH sigue viajando).
2. Es una SRH **inútil**: no queda ningún segmento por visitar, solo ocupa bytes y obliga a r3 a procesarla para llegar al IPv4. Con PSP (B2), r2 la quitaba y r3 recibía IPv6 limpio. Mismo resultado para el ping, pero con PSP se ahorran los bytes de la SRH y se descarga al último nodo.
3. (Se reactiva PSP con `ip -6 route replace ... action End flavors psp`.)

### Reto: USP en un End final

1. Depende de la versión. Un iproute2 reciente soporta `flavors psp`, `usp`, `usd` y combinaciones como `flavors psp,usp,usd`. Compruébalo con la ayuda de `ip route` o el `man` dentro del contenedor. Si alguna combinación no se instala, es una limitación de esa versión de kernel/iproute2.
2. Pondrías **`usp`**: *Ultimate Segment Pop* quita la SRH agotada pero **deja** el paquete tal cual (no desencapsula), de modo que el nodo lo siga reenviando por enrutamiento normal con su cabecera exterior ya limpia. **`usd`** desencapsularía (quitaría la IPv6 exterior y sacaría el interior), que es otra cosa: solo lo quieres si el tráfico venía encapsulado y hay que entregar el paquete interior.
3. Porque `End.DX4` y `End.DT6` pertenecen a la familia **`End.D*`**, cuya definición **ya incluye desencapsular** (USD implícito). Ponerles `usd` sería redundante. El flavor explícito solo tiene sentido en behaviors que por defecto **no** desencapsulan (`End`, `End.X`).
