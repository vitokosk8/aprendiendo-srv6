# 01 · Soluciones

> Las salidas de comandos son orientativas: las direcciones MAC, y por tanto las direcciones EUI-64, cambian en cada despliegue.

## Parte A

**A1.**

1. `2001:db8::1`
2. `2001:db8:0:1::1`. Hay dos secuencias de ceros (un grupo en la posición 3 y tres grupos en las posiciones 5 a 7); `::` va en la más larga.
3. `fe80::a8c1:abff:fe00:1`
4. `2001:db8:0:0:1::`. Hay dos secuencias de ceros: dos grupos en las posiciones 3–4 y tres grupos al final; `::` va en la de tres. Además, en minúsculas.

**A2.**

1. `0000:0000:0000:0000:0000:0000:0000:0001`
2. `2001:0db8:0000:0000:0000:0000:abcd:0001`
3. `fc00:0000:0002:e000:0000:0000:0000:0000`. Es el SID End.DT6 de r3 en nuestro laboratorio SRv6.

**A3.**

1. No. Tiene `::` dos veces y es imposible saber cuántos ceros hay en cada hueco.
2. No. Tiene 9 grupos (144 bits).
3. Sí. Es una link-local con *zone ID*. El `%eth1` no forma parte de la dirección: le dice al sistema por qué interfaz usarla.
4. No. `g` no es un dígito hexadecimal.

**A4.**

| Dirección | Tipo |
|-----------|------|
| `fe80::1` | Link-local |
| `2a00:1450:4003:80e::200e` | Unicast global (empieza por `2`, dentro de `2000::/3`) |
| `ff02::2` | Multicast: todos los routers del enlace |
| `fd12:3456:789a::1` | ULA (dentro de `fc00::/7`) |
| `::1` | Loopback |
| `5f00:0:2::` | SID de SRv6 (dentro de `5f00::/16`) |

**A5.**

```
aa:c1:ab:00:00:01
→ aa:c1:ab:ff:fe:00:00:01         (insertar ff:fe)
→ a8:c1:ab:ff:fe:00:00:01         (aa = 1010 1010 → invertir 7.º bit → 1010 1000 = a8)
→ IID a8c1:abff:fe00:0001
→ 2001:db8:1::a8c1:abff:fe00:1
```

**A6.** De /48 a /64 hay 16 bits, así que 2¹⁶ = **65.536 subredes**:

- Primera: `2001:db8:abcd::/64` (es decir, `2001:db8:abcd:0000::/64`)
- Segunda: `2001:db8:abcd:1::/64`
- Última: `2001:db8:abcd:ffff::/64`

## Parte B

### B1

Salida aproximada:

```
3: eth1@if4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9500 ...
    inet6 2001:db8:1::a8c1:abff:fe5d:2f10/64 scope global dynamic
       valid_lft 2591998sec preferred_lft 604798sec
    inet6 fe80::a8c1:abff:fe5d:2f10/64 scope link
       valid_lft forever preferred_lft forever
```

1. Dos: una **global** (`2001:db8:1::…`) y una **link-local** (`fe80::…`).
2. `scope link` significa que solo vale en este enlace; `scope global`, que puede usarse para comunicarse con cualquier red.
3. Por **SLAAC**: r1 anunció el prefijo `2001:db8:1::/64` en un *Router Advertisement* y h1 le añadió su propio identificador de interfaz. El `dynamic` y los tiempos `valid_lft`/`preferred_lft` indican que la dirección se obtuvo de un anuncio y que caduca si deja de renovarse.

### B2

Con una MAC como `aa:c1:ab:5d:2f:10`, el identificador EUI-64 es `a8c1:abff:fe5d:2f10`. **Sí coinciden**: la link-local y la global comparten exactamente la misma segunda mitad, porque las dos se construyen con el mismo identificador de interfaz; solo cambia el prefijo.

Containerlab asigna MACs que empiezan por `aa:c1:ab`, y por eso todas las link-local del curso empiezan por `fe80::a8c1:abff:fe…`. Ya lo viste en el laboratorio SRv6.

### B3

1. Una link-local `fe80::…/64`. Se genera automáticamente en cuanto IPv6 está activo en la interfaz, aunque nadie la configure.
2. Porque r1 es un router (`forwarding=1`), y Linux no acepta *Router Advertisements* en una interfaz con el reenvío activado (`accept_ra=1` solo actúa si `forwarding=0`). Además, él es quien envía los anuncios: no tendría sentido que se configurara con los suyos propios.

### B4

Salida aproximada:

```
2001:db8:1::/64 dev eth1 proto ra metric 256 expires 2591995sec pref medium
fe80::/64 dev eth1 proto kernel metric 256 pref medium
default via fe80::a8c1:abff:fe1e:9b3c dev eth1 proto ra metric 1024 expires 1795sec hoplimit 64 pref medium
```

1. El siguiente salto es la **link-local de r1**. En IPv6 es lo habitual: el RA llega desde la link-local del router, y h1 la usa como puerta de enlace.
2. `proto ra` indica que la ruta la instaló un *Router Advertisement*, no un administrador ni un protocolo de enrutamiento.
3. Toda interfaz con IPv6 tiene una ruta al prefijo link-local `fe80::/64` para poder hablar con sus vecinos de enlace.

### B5

1. Sin `%eth1` el sistema no sabe por qué interfaz enviar el paquete: `fe80::/64` existe en *todas* las interfaces con IPv6 (incluida `eth0`). Según la versión de `ping`, el primer comando da un error de argumento inválido o no recibe respuesta.
2. No. h2 está en **otro enlace** y las direcciones link-local nunca se reenvían: r1 descarta cualquier paquete con destino link-local que no sea suyo.

### B6

1. Responden dos direcciones link-local: la de **h1** (él mismo forma parte del grupo) y la de **r1**. `ping` en IPv6 usa la link-local como origen al enviar a un multicast de alcance de enlace.
2. No. `ff02::1` tiene alcance de **enlace** (el `2` de `ff02`), y r1 no reenvía multicast de enlace.
3. Si la global de h1 es `2001:db8:1::a8c1:abff:fe5d:2f10`, los últimos 24 bits son `5d:2f10` y el grupo es `ff02::1:ff5d:2f10`.
4. Porque la link-local y la global tienen **el mismo identificador de interfaz** (EUI-64), y por tanto los mismos últimos 24 bits. Un único grupo *solicited-node* sirve para las dos.

### B7

1. Dos saltos: primero r1 y después h2. En el traceroute aparece la dirección de r1 en el enlace por el que llega el paquete, **`2001:db8:1::1`**.
2. Su dirección **global** `2001:db8:1::…`. Según las reglas de selección de origen (RFC 6724), se elige una dirección del mismo alcance que el destino. Una link-local no sirve para un destino global, porque las respuestas no podrían volver a través de r1.

### B8

Salida aproximada:

```
IP6 (hlim 255, next-header ICMPv6 (58), payload length 56) fe80::a8c1:abff:fe1e:9b3c > ff02::1:
  [icmp6 sum ok] ICMP6, router advertisement, length 56
    hop limit 64, Flags [none], pref medium, router lifetime 1800s, ...
      prefix info option (3), length 32 (4): 2001:db8:1::/64, Flags [onlink, auto], valid time 2592000s, pref. time 604800s
      source link-address option (1), length 8 (1): aa:c1:ab:1e:9b:3c
```

1. Origen: la **link-local de r1**. Destino: **`ff02::1`**, todos los nodos del enlace.
2. `2001:db8:1::/64`.
3. `onlink`: el prefijo está directamente en este enlace, así que h1 puede hablar con esas direcciones sin pasar por el router. `auto`: h1 puede usar el prefijo para autoconfigurarse por SLAAC.

Fíjate también en `hlim 255`: los mensajes de Neighbor Discovery se envían siempre con *hop limit* 255, y el receptor los descarta si llegan con otro valor. Así se garantiza que vienen del mismo enlace (lo veremos en el módulo 03).

### B9

1. Tres: la link-local, la global SLAAC y la nueva ULA `fd00:1::10`.
2. `fd00:1::/64 dev eth1 proto kernel`. Al añadir una dirección con prefijo, el kernel instala automáticamente la ruta a esa red como "directamente conectada".
3. No. r1 no conoce `fd00:1::/64`, así que no tiene ruta hacia esa red. Además, h2 no tendría por dónde enviarlo: su única ruta por defecto apunta a r1. Para que funcionara habría que añadir en r1 una dirección o una ruta en `fd00:1::/64`. Lo veremos en el módulo 04, sobre enrutamiento.

### Reto

h1 genera inmediatamente una dirección nueva en `2001:db8:cafe::/64`, pero **la antigua `2001:db8:1::…` sigue ahí**. Una dirección SLAAC tiene dos temporizadores que el router anuncia en el RA:

- **Preferred lifetime** (aquí 7 días): mientras no caduca, la dirección se usa para conexiones nuevas.
- **Valid lifetime** (aquí 30 días): mientras no caduca, la dirección sigue existiendo y acepta tráfico.

Que el router deje de anunciar un prefijo no lo borra: la dirección vive hasta que caducan esos temporizadores. Para retirarlo, el router anuncia el prefijo antiguo con *lifetimes* a 0 (en FRR, `ipv6 nd prefix 2001:db8:1::/64 0 0`). Aun así, el host no la borra al instante: deja de usarla para conexiones nuevas, pero reduce su *valid lifetime* a 2 horas como mínimo. Es una protección del [RFC 4862 §5.5.3](https://www.rfc-editor.org/rfc/rfc4862#section-5.5.3) para que un RA falso no pueda dejar sin dirección a toda la red de golpe.

Este comportamiento es el que hace posible renumerar una red IPv6 sin cortes.
