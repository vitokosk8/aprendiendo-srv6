# 01 · Práctica: la dirección IPv6

Antes de empezar, lee la [teoría del módulo](README.md).

## Topología

```
        2001:db8:1::/64              2001:db8:2::/64
  ┌────┐               ┌────┐                ┌────┐
  │ h1 │eth1 ──── eth1│ r1 │eth2 ──── eth1│ h2 │
  └────┘               └────┘                └────┘
  (SLAAC)          ::1 en cada enlace         (SLAAC)
```

- **r1** es un router FRR con una dirección fija en cada enlace (`2001:db8:1::1` y `2001:db8:2::1`). Anuncia cada prefijo con *Router Advertisements*.
- **h1** y **h2** son hosts sin ninguna dirección configurada. Al arrancar, solo tendrán lo que se construyan ellos mismos.

## Parte A · Ejercicios en papel

Hazlos sin ordenador. Las soluciones están en [soluciones.md](soluciones.md).

**A1.** Comprime al máximo, en forma canónica:

1. `2001:0db8:0000:0000:0000:0000:0000:0001`
2. `2001:0db8:0000:0001:0000:0000:0000:0001`
3. `fe80:0000:0000:0000:a8c1:abff:fe00:0001`
4. `2001:0DB8:0000:0000:0001:0000:0000:0000`

**A2.** Expande a los 32 dígitos:

1. `::1`
2. `2001:db8::abcd:1`
3. `fc00:0:2:e000::`

**A3.** ¿Son válidas? Si no, explica por qué.

1. `2001:db8::1::2`
2. `2001:db8:0:0:0:0:0:0:1`
3. `fe80::1%eth1`
4. `2001:db8:g::1`

**A4.** Clasifica cada dirección según su tipo: `fe80::1`, `2a00:1450:4003:80e::200e`, `ff02::2`, `fd12:3456:789a::1`, `::1`, `5f00:0:2::`, `3fff:0:1::10`.

**A5.** Calcula la dirección EUI-64 que generará una interfaz con MAC `aa:c1:ab:00:00:01` en el prefijo `2001:db8:1::/64`.

**A6.** Te asignan `2001:db8:abcd::/48`. ¿Cuántas subredes /64 puedes crear? Escribe la primera, la segunda y la última.

## Parte B · Laboratorio

### B0. Levantar el laboratorio

```bash
$ cd 01-direccion-ipv6/lab
$ sudo containerlab deploy -t lab.clab.yml
```

Espera unos 15 segundos para que r1 envíe sus primeros *Router Advertisements* y comprueba que todo está bien:

```bash
$ ./verificar.sh
```

Si todas las comprobaciones salen en verde, empieza la práctica.

### B1. Las direcciones de h1

```bash
$ docker exec clab-m01-h1 ip -6 addr show dev eth1
```

1. ¿Cuántas direcciones IPv6 tiene `eth1`? ¿De qué tipo es cada una?
2. Fíjate en el campo `scope` de cada una. ¿Qué significa `scope link` y qué significa `scope global`?
3. h1 no tiene ninguna dirección configurada. ¿De dónde ha sacado su dirección global?

### B2. Comprobar EUI-64 con tus propios ojos

```bash
$ docker exec clab-m01-h1 ip link show dev eth1
```

1. Apunta la MAC de `eth1` (campo `link/ether`).
2. Calcula a mano su identificador EUI-64, como en el ejercicio A5.
3. Compáralo con las direcciones del paso B1. ¿Coinciden la link-local y la global en la segunda mitad?

### B3. Las direcciones de r1

```bash
$ docker exec clab-m01-r1 vtysh -c "show interface brief"
$ docker exec clab-m01-r1 ip -6 addr show dev eth1
```

1. r1 tiene configurada `2001:db8:1::1`. ¿Qué otra dirección tiene en `eth1` que no has configurado?
2. ¿Por qué r1 no tiene una dirección SLAAC como h1?

### B4. La tabla de rutas de h1

```bash
$ docker exec clab-m01-h1 ip -6 route
```

1. Busca la ruta por defecto (`default`). ¿Cuál es el siguiente salto? ¿Es global o link-local?
2. ¿Qué significa `proto ra`?
3. ¿Por qué hay una ruta hacia `fe80::/64`?

### B5. Link-local y el *zone ID*

Primero averigua la link-local de r1 en `eth1` (la viste en B3). Después:

```bash
$ docker exec clab-m01-h1 ping -c2 fe80::<IID-de-r1>
$ docker exec clab-m01-h1 ping -c2 fe80::<IID-de-r1>%eth1
```

1. ¿Por qué falla el primero y funciona el segundo?
2. Intenta hacer ping desde h1 a la link-local de **h2**. ¿Funciona? ¿Por qué?

### B6. Multicast: quién responde a `ff02::1`

```bash
$ docker exec clab-m01-h1 ping -c2 ff02::1%eth1
```

1. ¿Qué direcciones responden? ¿Quiénes son?
2. ¿Responde h2? ¿Por qué?

Ahora mira a qué grupos multicast pertenece h1:

```bash
$ docker exec clab-m01-h1 ip -6 maddr show dev eth1
```

3. Identifica `ff02::1` y el grupo *solicited-node* (`ff02::1:ff…`). Calcula a mano el *solicited-node* que corresponde a la dirección global de h1 y comprueba que está en la lista.
4. ¿Por qué h1 está en un único grupo *solicited-node* aunque tenga dos direcciones unicast?

### B7. De una red a otra

Averigua la dirección global de h2 y haz ping desde h1:

```bash
$ docker exec clab-m01-h2 ip -6 addr show dev eth1 scope global
$ docker exec clab-m01-h1 ping -c3 <dirección-global-de-h2>
$ docker exec clab-m01-h1 traceroute -6 -n <dirección-global-de-h2>
```

1. ¿Cuántos saltos hay? ¿Qué dirección de r1 aparece en el traceroute?
2. ¿Qué dirección de origen ha usado h1? ¿Por qué no ha usado la link-local?

### B8. Ver un Router Advertisement

Captura durante 15 segundos en h1:

```bash
$ docker exec clab-m01-h1 timeout 15 tcpdump -ni eth1 -vv 'icmp6 and ip6[40]==134'
```

El filtro `ip6[40]==134` selecciona los mensajes ICMPv6 de tipo 134, los *Router Advertisement*.

1. ¿Cuál es la dirección de origen del RA? ¿Y la de destino?
2. Busca la opción `prefix info`. ¿Qué prefijo anuncia y con qué longitud?
3. Busca los flags `onlink` y `auto`. ¿Qué crees que indica cada uno?

En el módulo 03 estudiaremos estos mensajes a fondo.

### B9. Añadir una dirección a mano

```bash
$ docker exec clab-m01-h1 ip -6 addr add fd00:1::10/64 dev eth1
$ docker exec clab-m01-h1 ip -6 addr show dev eth1
$ docker exec clab-m01-h1 ip -6 route
```

1. ¿Cuántas direcciones tiene ahora `eth1`?
2. ¿Qué ruta nueva ha aparecido y por qué?
3. ¿Puede h1 llegar a `fd00:1::10` desde h2? Pruébalo y razona la respuesta.

### B10. Limpieza

```bash
$ sudo containerlab destroy -t lab.clab.yml --cleanup
```

## Reto

Sin destruir el laboratorio, cambia en r1 el prefijo anunciado a h1 por `2001:db8:cafe::/64`:

```bash
$ docker exec -it clab-m01-r1 vtysh
r1# configure
r1(config)# interface eth1
r1(config-if)# ipv6 address 2001:db8:cafe::1/64
r1(config-if)# no ipv6 nd prefix 2001:db8:1::/64
r1(config-if)# ipv6 nd prefix 2001:db8:cafe::/64
r1(config-if)# end
```

Espera 10 segundos y mira las direcciones de h1. ¿Qué ha pasado con la dirección antigua? ¿Por qué no ha desaparecido al instante?
