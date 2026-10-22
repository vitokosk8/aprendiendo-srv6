# 07 · Soluciones

> Las salidas de comandos son orientativas y se ajustarán con las de una ejecución real del laboratorio.

## Parte A

**A1.** `5f00:0:3:e000::` con formato F3216:

```
5f00:0000 : 0003 : e000 : 0000:0000:0000:0000
└── bloque 32 ──┘  nodo  func   argumentos (64 bits)
```

- **Localizador** = bloque `5f00:0000` + nodo `0003` = `5f00:0:3::/48` (lleva a r3).
- **Función** = `e000`.
- **Argumentos** = `0`.

**A2.** La Segment List va en orden inverso al camino:

```
Segment List[0] = 5f00:0:c::   (C, el último)
Segment List[1] = 5f00:0:b::   (B)
Segment List[2] = 5f00:0:a::   (A, el primero)
Segments Left   = 2            (índice del primer SID a ejecutar, A)
Last Entry      = 2            (índice del último elemento)
Destino al salir = 5f00:0:a::  (el SID activo = A)
```

**A3.** Con 4 SID:
- **Hdr Ext Len** = 2 × 4 = **8** (unidades de 8 bytes, sin contar las 8 primeras).
- Tamaño de la SRH = 8 + 16 × 4 = **72 bytes**.
- Encap total añadido = 40 (IPv6 exterior) + 72 (SRH) = **112 bytes**.

**A4.**

| Punto | Destino exterior | SL |
|-------|------------------|----|
| sale de h1 | `5f00:0:2:e000::` | 1 |
| sale de r2 | `5f00:0:3:e000::` | 0 |
| llega a r3 | `5f00:0:3:e000::` | 0 |

**A5.** Porque el **SID activo va en la dirección de destino**, y un SID es una dirección IPv6 dentro de un prefijo enrutable (el localizador). r1 solo mira el destino `5f00:0:2:e000::`, hace *longest-prefix match* (encaja con `5f00:0:2::/48`, que el IGP le dice que está por r2) y reenvía. No abre la SRH ni sabe qué es. Es IPv6 normal.

## Parte B

### B1

1. `5f00:0:2:e000::` → localizador `5f00:0:2::/48`, lleva a **r2**. `5f00:0:3:e000::` → localizador `5f00:0:3::/48`, lleva a **r3**.
2. Los dos tienen función `e000`. **No significan lo mismo**: en r2, `e000` es un **End**; en r3, el mismo `e000` es un **End.DT6**. La función solo tiene sentido en el nodo dueño del SID; el mismo valor puede ser un behavior distinto en cada router.

### B2

1. El destino exterior es `5f00:0:2:e000::`, que **coincide con el primer SID del camino** (r2): es el SID activo.
2. `segleft = 1` y `lastentry = 1`. La `Segment List` está en **orden inverso**: `[0] = 5f00:0:3:e000::` (r3, el último) y `[1] = 5f00:0:2:e000::` (r2, el primero). SL=1 apunta al índice 1, que es r2.
3. El destino interior es `3fff:0:2::20` (h2), y dentro lleva el **ICMPv6 Echo Request** original.
4. El encap de 2 SID añade **80 bytes**: 40 (IPv6 exterior) + 8 (SRH fija) + 16 × 2 (SID).

### B3

1. **Entrada de r2**: destino exterior `5f00:0:2:e000::`, `segleft=1`. El SID activo es el de r2 (End). Se ve también la SRH con `[0]=r3, [1]=r2` y, dentro, el IPv6 interior hacia h2.
2. **Entrada de r3**: el destino exterior ha pasado a `5f00:0:3:e000::` y `segleft=0`. Lo cambió **r2** al ejecutar su behavior **End**: restó 1 a SL (1→0) y copió `Segment List[0]` (r3) al destino.
3. **Salida hacia h2**: es un **IPv6 normal**, sin SRH. En r3, el behavior **End.DT6** (con SL=0) desencapsuló: quitó la cabecera exterior y la SRH, y entregó el IPv6 interior (de h1 a h2) a la red de h2. h2 nunca ve SRv6.
4. El **Hop Limit exterior** baja en cada salto: entre la entrada de r2 y la de r3 ha bajado (lo restaron r1 y r2). El del **paquete interior** que llega a h2 **no cambió** en todo el túnel: para el cliente, todo el recorrido SRv6 fue un único salto.

### B4

1. r2: `encap seg6local action End`. r3: `encap seg6local action End.DT6 table 254`.
2. Porque el **longest-prefix match** elige siempre el prefijo más largo que encaje. El SID es `5f00:0:2:e000::/128` (una ruta de 128 bits) y la conectada es `5f00:0:2::/64`. Las dos encajan con `5f00:0:2:e000::`, pero la `/128` es más específica, así que gana y el paquete ejecuta el behavior End en vez de entregarse localmente.

### B5

1. Con un solo SID: 40 + 8 + 16 = **64 bytes**.
2. `segleft=0` y la `Segment List` tiene un único elemento, `[0]=5f00:0:3:e000::`, que además coincide con el destino exterior. Con un solo SID, la SRH es **redundante**: toda su información (el único SID) ya está en el destino. Por eso **H.Encaps.Red** la omite y el paquete queda en IPv6 exterior + IPv6 interior, sin SRH. El script la mantiene a propósito para que veas la estructura completa.

### B6

1. Con la lista invertida `[5f00:0:3:e000::, 5f00:0:2:e000::]`, el **primer** SID es el End.DT6 de r3. El paquete sale de h1 con destino `5f00:0:3:e000::`, llega a r3 y r3 ejecuta End.DT6 con `segleft=1` (todavía queda un segmento). End.DT6 desencapsula igualmente, pero el resultado no tiene sentido: se pierde el segundo segmento y el paquete interior se entrega (o se descarta) antes de tiempo. La respuesta **no llega** como en el orden correcto. La lección: el orden de la lista **es** el camino; invertirlo cambia por completo el comportamiento, porque cada SID ejecuta un behavior distinto en su nodo.

### Reto

En el volcado hexadecimal, empezando por la cabecera IPv6 exterior (los primeros 40 bytes):

- Byte 0: `6…` (versión 6). Byte **6** (el 7.º): `2b` = **43**, el Next Header → viene un Routing Header.
- Byte 7: el Hop Limit exterior.
- Bytes 8–23: dirección de origen (h1). Bytes 24–39: destino = `5f00:0:2:e000::`.
- A partir del byte 40, la **SRH**: `nh` (41, IPv6 interior), `Hdr Ext Len` (04 = 4, para 2 SID), **Routing Type `04`**, **Segments Left `01`**, **Last Entry `01`**, flags y tag.
- Luego los dos SID de 16 bytes: primero `[0]` = `5f00:0:3:e000::…` (r3) y después `[1]` = `5f00:0:2:e000::…` (r2). Comprueba que `[0]` es r3: la lista está al revés del camino.
- Tras la SRH, el IPv6 interior (otra cabecera de 40 bytes, destino `3fff:0:2::20`) y el ICMPv6.
