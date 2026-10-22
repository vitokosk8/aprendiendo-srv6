# 02 · Soluciones

> Las salidas son de una ejecución real del laboratorio. El Flow Label, los tiempos y algunos detalles pueden cambiar en la tuya.

## Parte A

**A1.**

| Bytes | Campo | Valor |
|-------|-------|-------|
| `6` | Version | 6 |
| `b8` | Traffic Class | 0xb8 |
| `12345` | Flow Label | 0x12345 |
| `0020` | Payload Length | 32 bytes |
| `00` | Next Header | 0 → detrás viene una **Hop-by-Hop** |
| `40` | Hop Limit | 64 |
| `3fff 0000 0001 … 0010` | Source Address | `3fff:0:1::10` (h1) |
| `3fff 0000 0002 … 0010` | Destination Address | `3fff:0:2::10` (h2) |

La primera palabra, `6b812345`, se lee en binario: `0110` (versión 6) + `1011 1000` (Traffic Class `b8`) + `0001 0010 0011 0100 0101` (Flow Label `12345`).

**A2.** `0xb8` = `1011 1000`. Los 6 bits altos, `101110`, son el DSCP = **46**, que corresponde a **EF** (*Expedited Forwarding*), la clase que se usa para la voz. Los 2 bits bajos, `00`, son el ECN = 0.

**A3.** ICMPv6 Echo Request = 8 bytes de cabecera + 56 de datos = 64 bytes.

- Payload Length = **64**.
- Paquete IPv6 = 40 + 64 = **104 bytes**.
- Trama Ethernet = 14 + 104 = **118 bytes** (sin contar el preámbulo ni el FCS).

**A4.**

| Cabecera | Next Header |
|----------|------------:|
| IPv6 | 0 (Hop-by-Hop) |
| Hop-by-Hop | 43 (Routing) |
| Routing | 44 (Fragment) |
| Fragment | 6 (TCP) |

**A5.**

1. Hop-by-Hop: **r1, r2 y h2**. Es la única que procesan todos los nodos del camino.
2. Destination Options: **solo h2**.
3. Routing Header con destino h2: **solo h2**. r1 y r2 solo miran la dirección de destino y reenvían.

**A6.** Los dos bits altos de cada tipo:

| Tipo | Binario | Bits altos | Acción |
|------|---------|:---:|--------|
| `0x1e` | `0001 1110` | 00 | Saltar la opción y seguir |
| `0x5e` | `0101 1110` | 01 | Descartar en silencio |
| `0x9e` | `1001 1110` | 10 | Descartar y enviar ICMPv6 Parameter Problem |
| `0xde` | `1101 1110` | 11 | Descartar y enviar Parameter Problem si el destino no era multicast |

**A7.** El mensaje ICMPv6 mide 8 + 3000 = 3008 bytes. Cada fragmento puede llevar como máximo 1400 − 40 − 8 = 1352 bytes de datos, que es múltiplo de 8.

| Fragmento | Datos | Tamaño total | Fragment Offset |
|-----------|------:|-------------:|-----------------|
| 1 | 1352 | 1400 | 0 |
| 2 | 1352 | 1400 | 1352 bytes (campo = 169) |
| 3 | 304 | 352 | 2704 bytes (campo = 338) |

El campo *Fragment Offset* cuenta en unidades de 8 bytes: 1352 / 8 = 169 y 2704 / 8 = 338.

**A8.** Una SRH tiene 8 bytes fijos más 16 por SID: 8 + 3 × 16 = **56 bytes**. *Hdr Ext Len* cuenta unidades de 8 bytes sin los 8 primeros: 48 / 8 = **6**. Al encapsular se añaden 40 (IPv6 exterior) + 56 (SRH) = **96 bytes**.

## Parte B

### B1

Salida aproximada en h2:

```
IP6 (flowlabel 0x3a2b1, hlim 62, next-header ICMPv6 (58), payload length 64) 3fff:0:1::10 > 3fff:0:2::10: [icmp6 sum ok] ICMP6, echo request, id 7, seq 1
```

1. Llega con **hlim 62**. Salió de h1 con 64 y cada router (r1 y r2) le ha restado 1.
2. `flowlabel` (Flow Label: Linux pone uno aleatorio por flujo), `hlim` (Hop Limit), `next-header ICMPv6 (58)` (Next Header), `payload length 64` (Payload Length), y las direcciones de origen y destino. El Traffic Class no aparece porque vale 0.

### B2

Salida real (resumida con `grep RESPUESTA`):

```
hoplimit 1 → RESPUESTA de 3fff:0:1::1:  type = Time exceeded, code = hop limit exceeded in transit
hoplimit 2 → RESPUESTA de 3fff:0:12::2: type = Time exceeded, code = hop limit exceeded in transit
hoplimit 3 → RESPUESTA de 3fff:0:2::10: ICMPv6 Echo Reply (id: 0x202 seq: 0x1)
```

1.
   - `hoplimit 1`: responde **r1** (`3fff:0:1::1`) con un ICMPv6 **Time Exceeded** (*hop limit exceeded in transit*). r1 resta 1, el Hop Limit llega a 0 y descarta el paquete.
   - `hoplimit 2`: responde **r2** con Time Exceeded. La dirección de origen será la de r2 en el enlace por el que sale la respuesta hacia h1, `3fff:0:12::2`.
   - `hoplimit 3`: el paquete llega a h2 con Hop Limit 1, suficiente para entregarse, y responde **h2** con un **Echo Reply**.
2. **traceroute**: envía paquetes con Hop Limit 1, 2, 3… y apunta quién devuelve cada Time Exceeded.

### B3

1. Sí. La captura en h2 muestra `class 0xb8` en un caso y `flowlabel 0x12345` en el otro.
2. No. Los routers solo modifican el Hop Limit. Traffic Class y Flow Label llegan tal y como los puso h1. (En una red con QoS, un router de borde sí podría reescribir el DSCP, pero no es el caso aquí.)

### B4

La salida de `-x` empieza por la cabecera IPv6, sin la cabecera Ethernet:

```
0x0000:  6003 a2b1 0040 3a3e 3fff 0000 0001 0000
0x0010:  0000 0000 0000 0010 3fff 0000 0002 0000
0x0020:  0000 0000 0000 0010 8000 ...
```

- `6` versión, `00` Traffic Class, `3a2b1` Flow Label.
- `0040` Payload Length = 64.
- `3a` Next Header = 58 (ICMPv6), `3e` Hop Limit = 62.
- Origen `3fff:0:1::10` y destino `3fff:0:2::10`.
- Justo después, `80` = 128: el tipo ICMPv6 *Echo Request*.

### B5

1. `hbh-saltar`: responde **h2** con un Echo Reply:

   ```
   RESPUESTA de 3fff:0:2::10: ICMPv6 Echo Reply (id: 0x202 seq: 0x1)
   ```

   r1, r2 y h2 ven la opción, no la reconocen y, como sus bits altos son `00`, la saltan.

   `hbh-descartar`: responde **r1** (`3fff:0:1::1`) con un ICMPv6 **Parameter Problem**:

   ```
   RESPUESTA de 3fff:0:1::1
        type      = Parameter problem
        code      = unrecognized IPv6 option encountered
        ptr       = 42
   ```

   Scapy también decodifica la opción que provocó el error: `otype = 158 [10: discard+ICMP, 0: Don't change en-route]`. 158 es `0x9e`, y los bits `10` son los que ordenan descartar y avisar.
2. `ptr` = **42**: el byte 42 del paquete es el tipo de la opción (40 bytes de cabecera IPv6 + 2 bytes de cabecera Hop-by-Hop).
3. Porque **r1** procesa la Hop-by-Hop, como todos los nodos del camino. Encuentra una opción desconocida con bits `10`, descarta el paquete y avisa. Nunca llega a r2.

### B6

`dst-saltar` llega sin problemas: `RESPUESTA de 3fff:0:2::10: ICMPv6 Echo Reply (id: 0x202 seq: 0x1)`.

1. **h2** (`3fff:0:2::10`) responde con *Parameter problem*, `code = unrecognized IPv6 option encountered`, `ptr = 42`. El mismo error que en B5, pero ahora lo genera el destino.
2. El paquete ha atravesado r1 y r2 sin problemas, aunque llevaba la misma opción desconocida que en B5. Los routers **no abren** las cabeceras de extensión, salvo Hop-by-Hop: miran el destino y reenvían. Es la regla que hace posible SRv6.

### B7

1. **h2** responde con *Parameter problem*, `code = erroneous header field encountered`, `ptr = 42`. El byte 42 es el campo *Routing Type* del Routing Header (40 de la cabecera IPv6 + 2: *Next Header* y *Hdr Ext Len*).
2. Porque el Routing Header tipo 0 está prohibido desde el RFC 5095. Un nodo que recibe uno con *Segments Left* > 0 lo trata como un tipo desconocido y avisa al origen. Si *Segments Left* fuera 0, lo ignoraría y procesaría el resto del paquete.

### B8

1. **No responde** (`RESPUESTA: ninguna en 3 segundos`). h2 descarta el paquete en silencio, sin enviar ningún error.
2. Las dos claves valen **0**: SRv6 está desactivado.
3. Con `seg6_enabled=1` la respuesta cambia:

   ```
   RESPUESTA de 3fff:0:2::10: ICMPv6 Echo Reply (id: 0x202 seq: 0x1)
   ```

   h2 acepta la SRH. Como *Segments Left* = 0, no hay nada más que hacer con ella y procesa la cabecera siguiente: el ICMPv6 Echo Request. h2 responde con un **Echo Reply**.

   Linux es más estricto que el RFC: descarta **cualquier** paquete con SRH si SRv6 no está activado en la interfaz de entrada, aunque *Segments Left* sea 0. Es una medida de seguridad: un nodo que no forma parte del dominio SRv6 no debe aceptar paquetes con SRH, para que nadie pueda usarlo desde fuera. Por eso, en los laboratorios SRv6, siempre activamos `seg6_enabled` en las interfaces del dominio.

### B9

1.

   ```
   IPv6 (Next Header 0) → Hop-by-Hop (Next Header 60) → Destination Options (Next Header 58) → ICMPv6
   ```

   `tcpdump` lo muestra en una línea: `next-header Options (0)`, `HBH (…)`, `DSTOPT (…)` y finalmente `ICMP6, echo request`.
2. Payload Length = **40**: 8 (Hop-by-Hop) + 8 (Destination Options) + 24 (ICMPv6: 8 de cabecera + 16 de datos, el texto `aprendiendo-srv6`).

### B10

Salida real del primer `ping -c3 -s 2000` con el laboratorio recién levantado:

```
PING 3fff:0:2::10 (3fff:0:2::10) 2000 data bytes
From 3fff:0:1::1 icmp_seq=1 Packet too big: mtu=1400
2008 bytes from 3fff:0:2::10: icmp_seq=3 ttl=62 time=0.240 ms

--- 3fff:0:2::10 ping statistics ---
3 packets transmitted, 1 received, +1 errors, 66.6667% packet loss
```

1. El primer ping falla con `Packet too big: mtu=1400`, enviado por **r1** (`3fff:0:1::1`), que no puede reenviar 2048 bytes por un enlace de MTU 1400. Fíjate en que **el segundo también se pierde**, sin error visible: h1 ya fragmenta y el *echo request* llega a h2, pero el *echo reply* de h2 (también de 2048 bytes) choca con la misma MTU en r2, que avisa a **h2**, no a h1. Solo a partir del tercero los dos extremos conocen la MTU del camino y todo funciona.
2. Después aparece la MTU aprendida:

   ```
   3fff:0:2::10 via 3fff:0:1::1 dev eth1 src 3fff:0:1::10 metric 1024 expires 587sec mtu 1400 pref medium
   ```

   `mtu 1400` es la MTU del camino que h1 ha aprendido, y `expires 587sec`, el tiempo que le queda a esa información (unos 10 minutos en total). Cuando caduque, h1 volverá a probar con paquetes grandes. Si repites el ping antes, los tres funcionan a la primera.
3. Dos fragmentos por cada *echo request*:

   ```
   IP6 (… payload length 1360) 3fff:0:1::10 > 3fff:0:2::10: frag (0|1352) ICMP6, echo request, …
   IP6 (… payload length 664)  3fff:0:1::10 > 3fff:0:2::10: frag (1352|656)
   ```

   `frag (0|1352)` significa "offset 0, 1352 bytes de datos". Cada fragmento mide 40 + 8 + 1352 = 1400 bytes y 40 + 8 + 656 = 704 bytes, como en la teoría. El Payload Length incluye los 8 bytes de la Fragment Header.
4. Porque el camino de vuelta tiene el mismo cuello de botella, como se ve en la pérdida del segundo ping: r2 envía un Packet Too Big a h2 y, a partir de entonces, h2 también fragmenta sus respuestas.

### Reto

El ping de 2000 bytes deja de funcionar y **no aparece ningún error**: r1 descarta el paquete grande y el aviso no llega a h1, que sigue enviando paquetes de 2048 bytes que nunca pasan. El ping de 1000 bytes funciona sin problemas porque cabe en la MTU de 1400.

Es el clásico **agujero negro de PMTUD**. Una conexión TCP establece la sesión con paquetes pequeños (todo parece funcionar) y se cuelga en cuanto intenta enviar un paquete grande. Por eso el [RFC 4890](https://www.rfc-editor.org/rfc/rfc4890) dice que el ICMPv6 *Packet Too Big* nunca debe filtrarse.
