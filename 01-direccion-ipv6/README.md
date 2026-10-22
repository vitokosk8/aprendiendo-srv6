# 01 · La dirección IPv6

> **Objetivo**: entender qué es una dirección IPv6, saber leerla y escribirla, reconocer sus tipos y saber cómo la obtiene un equipo.
> **Por qué importa para SRv6**: en SRv6 *cada instrucción es una dirección IPv6*. Si no lees las direcciones con soltura, no podrás leer un paquete SRv6.

## 1. ¿Qué es una dirección IP?

Una red necesita saber **a quién** va dirigido cada paquete. Para eso cada interfaz conectada recibe un identificador numérico: su **dirección IP**. Cada paquete lleva dos: la de **origen** (quién lo envía) y la de **destino** (a quién va).

Los routers miran la dirección de destino y deciden por dónde reenviar el paquete. Esa idea tan sencilla —*el router decide mirando la dirección de destino*— es la base de todo el curso. En SRv6 la aprovecharemos de una forma muy ingeniosa.

## 2. Por qué IPv6

IPv4 usa direcciones de **32 bits**: unos 4.300 millones de combinaciones, que se agotaron. Los registros regionales (RIPE NCC en Europa) ya no tienen bloques IPv4 libres que repartir, y gran parte de Internet sobrevive gracias al NAT.

IPv6 usa direcciones de **128 bits**:

| | Bits | Direcciones posibles |
|---|---:|---:|
| IPv4 | 32 | 2³² ≈ 4,3 × 10⁹ |
| IPv6 | 128 | 2¹²⁸ ≈ 3,4 × 10³⁸ |

No es "un poco más": es tanto espacio que la forma de diseñar las redes cambia. Por ejemplo, **cada subred LAN recibe 2⁶⁴ direcciones**, más que todo Internet IPv4 al cuadrado. Ese espacio sobrante es justo lo que SRv6 usa para codificar instrucciones dentro de las direcciones.

## 3. Cómo se escribe

### Hexadecimal y grupos

128 bits en binario serían ilegibles, así que se escriben en **hexadecimal**: cada dígito hexadecimal (0–9, a–f) representa **4 bits**. 128 bits son 32 dígitos, que se agrupan de 4 en 4 separados por `:`. Cada grupo de 16 bits se llama a veces *hexteto*.

```
2001:0db8:0000:0000:0000:ff00:0042:8329
└──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘
 16   16   16   16   16   16   16   16  = 128 bits
```

Recordatorio de hexadecimal: `a`=10, `b`=11, `c`=12, `d`=13, `e`=14, `f`=15. Así `ff` = 255 y `0x10` = 16.

### Las dos reglas de compresión

Escribir 32 dígitos es incómodo. El [RFC 5952](https://www.rfc-editor.org/rfc/rfc5952) define cómo abreviar:

**Regla 1 — Ceros a la izquierda.** En cada grupo se pueden quitar los ceros iniciales:

```
2001:0db8:0000:0000:0000:ff00:0042:8329
2001: db8:   0:   0:   0:ff00:  42:8329   →  2001:db8:0:0:0:ff00:42:8329
```

**Regla 2 — Una secuencia de grupos a cero se sustituye por `::`**, pero **solo una vez** por dirección (si no, sería imposible saber cuántos ceros hay en cada hueco):

```
2001:db8:0:0:0:ff00:42:8329   →   2001:db8::ff00:42:8329
```

Para expandir una dirección comprimida, se cuentan los grupos que hay y `::` vale los que falten hasta 8:

```
2001:db8::1   → 3 grupos escritos → :: vale 5 grupos
              → 2001:0db8:0000:0000:0000:0000:0000:0001
```

El RFC 5952 fija además una forma *canónica* para que todos escribamos igual: minúsculas, `::` en la secuencia de ceros más larga (y la primera si empatan), y no usar `::` para un único grupo a cero.

| Correcto | Incorrecto | Por qué |
|----------|------------|---------|
| `2001:db8::1` | `2001:DB8::1` | Minúsculas |
| `2001:db8:0:1::1` | `2001:db8::1:0:0:0:1` | `::` en la secuencia de ceros más larga |
| `2001:db8:0:1:1:1:1:1` | `2001:db8::1:1:1:1:1` | `::` no sustituye un solo grupo |

## 4. Prefijo e identificador de interfaz

Como en IPv4, una dirección tiene dos partes, y la **longitud de prefijo** (`/n`) indica dónde se corta:

```
2001:db8:1:0 : 0:0:0:10 /64
└─ prefijo ─┘  └─ ID de interfaz ─┘
 64 bits: la red      64 bits: el equipo dentro de esa red
```

- El **prefijo** identifica la red. Es lo que aparece en las tablas de rutas.
- El **identificador de interfaz** (IID) identifica el equipo dentro de esa red.

En IPv6 la norma general es que **una LAN es un /64**. Un ISP suele entregar a un cliente un /48 o un /56, y el cliente lo trocea en /64. Fíjate en lo cómodo que es trocear por múltiplos de 4 bits, porque coinciden con un dígito hexadecimal:

```
2001:db8:abcd::/48        ← lo que recibe un cliente
2001:db8:abcd:0001::/64   ← subred 1
2001:db8:abcd:0002::/64   ← subred 2
...
2001:db8:abcd:ffff::/64   ← subred 65.536
```

> **Conexión con SRv6**: un *locator* de SRv6 es exactamente esto, un prefijo (por ejemplo `fc00:0:2::/48`) que se anuncia y se enruta como cualquier otro. Lo que hay detrás del prefijo no identifica un equipo, sino una *instrucción*.

## 5. Tipos de direcciones

IPv6 **no tiene broadcast**. Hay tres clases de dirección:

- **Unicast**: identifica una interfaz. El paquete llega a esa interfaz.
- **Multicast**: identifica un grupo. El paquete llega a todos los miembros.
- **Anycast**: una dirección unicast asignada a varios equipos. El paquete llega al más cercano.

Y estos son los rangos que hay que reconocer a simple vista:

| Rango | Tipo | Para qué sirve |
|-------|------|----------------|
| `::/128` | No especificada | "Todavía no tengo dirección". Solo como origen, por ejemplo al arrancar |
| `::1/128` | Loopback | El propio equipo, como `127.0.0.1` en IPv4 |
| `2000::/3` | Unicast global (GUA) | Direcciones públicas, enrutables en Internet |
| `2001:db8::/32` | Documentación | Reservado para ejemplos y laboratorios ([RFC 3849](https://www.rfc-editor.org/rfc/rfc3849)). Nunca se enruta en Internet |
| `fe80::/10` | Link-local | Válida solo en el enlace. **Toda interfaz IPv6 tiene una** |
| `fc00::/7` | Unique Local (ULA) | Privadas, similares a `10.0.0.0/8`. En la práctica se usa `fd00::/8` |
| `ff00::/8` | Multicast | Grupos. `ff02::` = alcance de enlace |
| `5f00::/16` | SIDs de SRv6 | Reservado para identificadores de SRv6 ([RFC 9602](https://www.rfc-editor.org/rfc/rfc9602)) |

### Link-local: la que siempre está

En cuanto se activa IPv6 en una interfaz, esta se genera automáticamente una dirección `fe80::/64`. Tiene dos propiedades clave:

1. **Solo vale en ese enlace.** Un router nunca reenvía un paquete con origen o destino link-local a otro enlace.
2. **Es ambigua**: todas las interfaces de un equipo tienen una dirección `fe80::…`, así que para usarla hay que decir **por qué interfaz**. Eso se indica con el *zone ID*: `fe80::1%eth1`.

Los protocolos de enrutamiento (IS-IS, OSPFv3, BGP *unnumbered*) usan las link-local como siguiente salto. En el laboratorio SRv6 que ya montamos, todas las rutas IS-IS apuntaban a `via fe80::…`, y los enlaces entre routers no tenían ninguna dirección global.

### Multicast: los grupos que importan

| Dirección | Grupo |
|-----------|-------|
| `ff02::1` | Todos los nodos del enlace |
| `ff02::2` | Todos los routers del enlace |
| `ff02::1:ffXX:XXXX` | *Solicited-node*: se forma con los últimos 24 bits de una dirección unicast. Lo usa Neighbor Discovery (módulo 03) |

Ejemplo de *solicited-node*: para `2001:db8:1::a8c1:abff:fe12:3456`, los últimos 24 bits son `12:3456`, así que el grupo es `ff02::1:ff12:3456`.

## 6. Una interfaz, varias direcciones

En IPv4 una interfaz suele tener una dirección. En IPv6 lo normal es que tenga **varias a la vez**:

```
eth1:
  fe80::a8c1:abff:fe12:3456/64        ← link-local (siempre)
  2001:db8:1:0:a8c1:abff:fe12:3456/64 ← global, autoconfigurada
  fd00:1::10/64                       ← ULA, configurada a mano
  + pertenece a ff02::1, ff02::1:ff12:3456, …
```

El sistema elige cuál usar como origen según el destino (las reglas están en el [RFC 6724](https://www.rfc-editor.org/rfc/rfc6724)).

## 7. Cómo obtiene un equipo su dirección

| Método | Cómo funciona |
|--------|---------------|
| **Manual** | Se configura a mano. Habitual en routers y servidores |
| **SLAAC** | El router anuncia el prefijo en un *Router Advertisement* (RA) y el equipo se construye la dirección él solo: prefijo + su propio IID ([RFC 4862](https://www.rfc-editor.org/rfc/rfc4862)) |
| **DHCPv6** | Un servidor asigna la dirección, como en IPv4 ([RFC 8415](https://www.rfc-editor.org/rfc/rfc8415)) |

### El identificador de interfaz EUI-64

Con SLAAC, ¿de dónde sale el identificador de interfaz? El método clásico, **EUI-64**, lo deriva de la dirección MAC:

```
MAC:            aa:c1:ab:12:34:56
1. Partir en dos y meter ff:fe en medio:
                aa:c1:ab:ff:fe:12:34:56
2. Invertir el bit "U/L" (el 7.º bit del primer byte):
   aa = 1010 1010  →  1010 1000 = a8
                a8:c1:ab:ff:fe:12:34:56
3. Agrupar de 16 en 16 bits:
   IID = a8c1:abff:fe12:3456
```

Así, con el prefijo `2001:db8:1::/64` la dirección SLAAC es `2001:db8:1::a8c1:abff:fe12:3456`, y la link-local es `fe80::a8c1:abff:fe12:3456`.

EUI-64 tiene un problema: la MAC viaja dentro de la dirección, y un equipo puede ser rastreado allá donde se conecte. Por eso los sistemas operativos de escritorio usan hoy identificadores aleatorios o *stable privacy* ([RFC 7217](https://www.rfc-editor.org/rfc/rfc7217), [RFC 8981](https://www.rfc-editor.org/rfc/rfc8981)). Linux en un contenedor usa EUI-64 por defecto, y en el laboratorio lo podrás comprobar con tus propios ojos.

## 8. Resumen

- Una dirección IPv6 tiene **128 bits**, se escribe en **8 grupos hexadecimales** y se comprime quitando ceros a la izquierda y usando `::` **una sola vez**.
- Se divide en **prefijo** (la red) e **identificador de interfaz** (el equipo). Una LAN es un **/64**.
- No hay broadcast: hay **unicast, multicast y anycast**.
- Toda interfaz tiene una **link-local** `fe80::`, que necesita el *zone ID* (`%eth1`) y que los protocolos de enrutamiento usan como siguiente salto.
- Una interfaz tiene **varias direcciones** a la vez.
- Un equipo obtiene su dirección **a mano, por SLAAC o por DHCPv6**.

## Siguiente paso

Haz la [práctica](practica.md) con el laboratorio de este módulo.

## Para saber más

- [RFC 4291](https://www.rfc-editor.org/rfc/rfc4291) — Arquitectura de direccionamiento IPv6
- [RFC 5952](https://www.rfc-editor.org/rfc/rfc5952) — Representación textual de direcciones IPv6
- [RFC 4862](https://www.rfc-editor.org/rfc/rfc4862) — SLAAC
- [RFC 9602](https://www.rfc-editor.org/rfc/rfc9602) — Bloque `5f00::/16` para SIDs de SRv6
- [SRv6.md · ¿Qué es SRv6?](https://srv6.md/es/que-es-srv6/)
