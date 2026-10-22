# 03 · Soluciones

> Las salidas de comandos son orientativas y se ajustarán con las de una ejecución real del laboratorio. Las MAC cambian en cada despliegue.

## Parte A

**A1.** El grupo solicited-node usa los últimos 24 bits; la MAC multicast, los últimos 32 bits del grupo.

| Dirección | Solicited-node | MAC multicast |
|-----------|----------------|---------------|
| `3fff:0:10::20` | `ff02::1:ff00:20` | `33:33:ff:00:00:20` |
| `3fff:0:10::1` | `ff02::1:ff00:1` | `33:33:ff:00:00:01` |
| `fe80::a8c1:abff:fe4e:e3b3` | `ff02::1:ff4e:e3b3` | `33:33:ff:4e:e3:b3` |

**A2.** `ff02::1` → `33:33:00:00:00:01`. `ff02::2` → `33:33:00:00:00:02`.

**A3.**

| Situación | Mensaje | Origen | Destino |
|-----------|---------|--------|---------|
| 1. Buscar router | RS | link-local de h1 | `ff02::2` (todos los routers) |
| 2. Resolver la MAC de h2 | NS | `3fff:0:10::10` (o la link-local de h1) | `ff02::1:ff00:20` (solicited-node de h2) |
| 3. DAD de `::33` | NS | `::` (no especificada) | `ff02::1:ff00:33` |
| 4. Comprobar un vecino en STALE | NS (tras DELAY, en PROBE) | `3fff:0:10::10` | `3fff:0:10::20`, **unicast**, a la MAC que ya conoce |

**A4.** h1 sabe que `3fff:0:40::40` no está en su enlace, así que se lo entrega a su router por defecto: pregunta por la MAC de **r1**, en concreto por la de su link-local. r1, al reenviar el paquete por eth2, pregunta por la MAC de **h4**. Cada salto resuelve solo la MAC del siguiente equipo de su propio enlace.

**A5.** Porque el NA tiene que llegar con **Hop Limit 255**. Si viene de otra red, al menos un router le ha restado 1 por el camino, y h1 lo descarta. Esta regla es la razón por la que las anomalías de ND solo pueden originarse dentro de la propia LAN.

**A6.** Deja de funcionar **toda la comunicación** del host: sin NS y NA no puede averiguar la MAC de nadie, ni siquiera de su router. Tampoco funciona DAD. Es como bloquear ARP en IPv4.

## Parte B

### B1

Salida aproximada en h2:

```
aa:c1:ab:11:11:11 > 33:33:ff:00:00:20, ethertype IPv6 (0x86dd), length 86:
  (hlim 255, next-header ICMPv6 (58), payload length 32) 3fff:0:10::10 > ff02::1:ff00:20:
  [icmp6 sum ok] ICMP6, neighbor solicitation, length 32, who has 3fff:0:10::20
    source link-address option (1), length 8 (1): aa:c1:ab:11:11:11
aa:c1:ab:22:22:22 > aa:c1:ab:11:11:11, ethertype IPv6 (0x86dd), length 86:
  (hlim 255, next-header ICMPv6 (58), payload length 32) 3fff:0:10::20 > 3fff:0:10::10:
  [icmp6 sum ok] ICMP6, neighbor advertisement, length 32, tgt is 3fff:0:10::20, Flags [solicited, override]
    destination link-address option (2), length 8 (1): aa:c1:ab:22:22:22
```

1. **IPv6**: de `3fff:0:10::10` (h1) a `ff02::1:ff00:20` (solicited-node de h2). **MAC**: de la MAC de h1 a `33:33:ff:00:00:20`. Pregunta por `3fff:0:10::20`. Fíjate también en `hlim 255`.
2. La opción **source link-address** con la MAC de h1. Así h2 ya sabe a qué MAC responder sin tener que preguntar a su vez.
3. Va dirigido a **h1 en unicast** (IPv6 y MAC de h1). Lleva los flags **solicited** (es la respuesta a un NS) y **override** (h1 debe sustituir lo que tuviera). No lleva **router**, porque h2 no es un router.
4. `3fff:0:10::20 lladdr aa:c1:ab:22:22:22 REACHABLE`.

### B2

1. h3 ve el **NS**, pero **no el NA**. El NS va a una dirección multicast, y sw1, con el snooping desactivado, lo inunda por todos sus puertos. El NA va en unicast a la MAC de h1, y el switch, que ya ha aprendido en qué puerto está h1, solo lo entrega por ese puerto.
2. No. La dirección preguntada no es suya.
3. La salida de `ip maddr` muestra algo como:

   ```
   3:  eth1
       link  33:33:00:00:00:01
       link  33:33:ff:00:00:30
       link  33:33:ff:xx:xx:xx
       inet6 ff02::1:ff00:30
       inet6 ff02::1:ffxx:xxxx
       inet6 ff02::1
   ```

   La tarjeta solo acepta `33:33:00:00:00:01` (todos los nodos) y los solicited-node de sus propias direcciones (`::30` y la link-local). **No** está suscrita a `33:33:ff:00:00:20`, así que, sin `tcpdump`, la tarjeta descartaría el NS de B1 y el sistema operativo no llegaría a verlo.

### B3

1. Alrededor de **30 segundos** (en Linux, un valor aleatorio entre 15 y 45). Después la entrada pasa a `STALE`.
2. `STALE` → **`DELAY`** (unos 5 segundos) → **`PROBE`** (un instante) → **`REACHABLE`**.
3. El NS va ahora en **unicast**: a `3fff:0:10::20` y a la MAC de h2, no al grupo solicited-node. h1 ya conoce la MAC; solo quiere confirmar que h2 sigue ahí.
4. Porque una entrada en `STALE` **se sigue usando**. El paquete sale de inmediato con la MAC guardada, y la comprobación se hace en paralelo. La respuesta del ping no sirve como confirmación, porque NUD solo acepta un NA o una confirmación de la capa superior (como los ACK de TCP); por eso, tras el `DELAY`, h1 pregunta igualmente.

### B4

1. A la **dirección link-local de r1**, que es su router por defecto. h1 no pregunta nunca por la MAC de h4.
2. Después del ping, la caché de h1 tiene una entrada para r1, no para h4:

   ```
   fe80::a8c1:abff:feXX:XXXX lladdr aa:c1:ab:rr:rr:rr router REACHABLE
   ```

   La palabra **`router`** indica que ese vecino se anunció como router (en su RA o en el flag R de su NA). h4 no aparece: está en otra red y h1 nunca resuelve su MAC.

### B5

Un RA periódico se ve así (capturado en h1):

```
(hlim 255, next-header ICMPv6 (58), payload length 56) fe80::a8c1:abff:fe3a:7c1c > ff02::1:
  ICMP6, router advertisement, length 56
    hop limit 64, Flags [none], pref medium, router lifetime 30s, reachable time 0ms, retrans timer 0ms
      prefix info option (3), length 32 (4): 3fff:0:10::/64, Flags [onlink], valid time 2592000s, pref. time 604800s
      source link-address option (1), length 8 (1): aa:c1:ab:3a:7c:1c
```

1. El RA sale de la **link-local de r1** (`fe80::…`) y va a **`ff02::1`** (todos los nodos). Llega con **Hop Limit 255**, como todo mensaje ND.
2. **Router lifetime 30 s** (3 × el intervalo de 10 s): si r1 dejara de anunciarse, los hosts lo quitarían como router por defecto a los 30 s. El prefijo es `3fff:0:10::/64` con el flag **onlink** (está en este enlace). La última opción es la **MAC de r1**. Ojo: el `hop limit 64` que aparece dentro del RA es un campo *de datos* (el valor que r1 sugiere a los hosts para sus paquetes), no el Hop Limit del propio paquete, que es 255.
3. El prefijo **no** lleva el flag `auto` porque en el laboratorio desactivamos la autoconfiguración (`net.ipv6.conf.default.autoconf: 0` en el `lab.clab.yml`). Así los hosts usan las direcciones fijas que les asignamos (`::10`, `::20`, `::30`) en lugar de generar una por SLAAC. Sí aprenden el router por defecto, porque eso no depende de ese flag.

> Si pruebas a enviar un RS con Hop Limit distinto de 255, verás que r1 **no** lo rechaza por ese motivo: el kernel de este laboratorio no comprueba la regla. En una implementación que sí la aplique, el RS se descartaría sin respuesta.

### B6

1. El NS de h3 lleva como origen la dirección **no especificada `::`**, porque h3 todavía no tiene una dirección válida en ese prefijo: la está comprobando.
2. Responde **h2** con un NA a **`ff02::1`** (todos los nodos, MAC `33:33:00:00:00:01`), no en unicast: como el NS venía de `::`, h2 no tiene a quién responder en concreto y avisa a toda la red. Capturado desde h1 (un tercero en la LAN):

   ```
   aa:c1:ab:4f:e4:a9 > 33:33:00:00:00:01: 3fff:0:10::20 > ff02::1:
     ICMP6, neighbor advertisement, tgt is 3fff:0:10::20
   ```

   (Si capturas en el propio h2 quizá solo veas el NS entrante: Linux no siempre muestra en `tcpdump` el multicast que él mismo genera. Captura en h1 o h3 para ver el NA de defensa.)
3. La dirección queda en estado **`dadfailed`** y **no se puede usar**:

   ```
   inet6 3fff:0:10::20/64 scope global tentative dadfailed
   ```

4. No. h2 sigue funcionando con normalidad; el ping desde h1 recibe respuesta. DAD ha protegido al que ya tenía la dirección.

### B7

1. `ping` termina con `100% packet loss`. Si le das tiempo suficiente (sin `-W1`), muestra además:

   ```
   From 3fff:0:10::10 icmp_seq=1 Destination unreachable: Address unreachable
   ```

   Lo genera **el propio h1**: tras agotar los NS sin respuesta, concluye que nadie tiene esa dirección en el enlace.
2. Justo después de rendirse, la entrada queda un instante en **`INCOMPLETE`** y a los pocos segundos pasa a **`FAILED`**:

   ```
   3fff:0:10::99 dev eth1 INCOMPLETE      ← al momento
   3fff:0:10::99 dev eth1 FAILED          ← unos segundos después
   ```

   h1 ha enviado **3 NS** (el valor por defecto de `net.ipv6.neigh.eth1.mcast_solicit`) antes de rendirse. Con un timeout corto (`ping -W1`), `ping` no llega a imprimir el texto *Destination unreachable*: simplemente termina con `100% packet loss`.

### B8

1. h3 envía un **informe MLDv2** (*Multicast Listener Report v2*) a **`ff02::16`** (todos los routers con MLDv2), desde su link-local y con **Hop Limit 1**. Capturado en h2:

   ```
   (hlim 1, next-header Options (0)) fe80::… > ff02::16: HBH (rtalert: 0x0000) (padn)
     ICMP6, multicast listener report v2, 3 group record(s)
       [gaddr ff02::1:ff00:33 to_ex { }] [gaddr ff02::1:ff00:30 to_ex { }] [gaddr ff02::1:ff65:8c28 to_ex { }]
   ```

   A diferencia de MLDv1, el informe va a `ff02::16` (no al grupo) y lleva **varios registros de grupo** en un solo mensaje.
2. Entre los registros aparece el **solicited-node de la nueva dirección**, `ff02::1:ff00:33` (los otros dos son los de sus direcciones anteriores). Al configurar `3fff:0:10::33`, h3 debe empezar a escuchar los NS dirigidos a su solicited-node, y avisa con MLD para que switches y routers con snooping le entreguen ese multicast.
3. La cabecera **Hop-by-Hop** lleva la opción **Router Alert**, para que los routers examinen el informe aunque no vaya dirigido a ellos.
4. `ip -6 maddr` muestra ahora `ff02::1:ff00:33` entre los grupos de eth1.

### Reto

h1 pasa a tener en su caché la **MAC de h3** asociada a `3fff:0:10::20`, porque el NA llega con el flag **override** y h1 sustituye la entrada. A partir de ese momento los paquetes que h1 destina a h2 se entregan en la tarjeta de h3, que es lo que ves en la captura; h2 deja de recibirlos y el ping se interrumpe.

Unos segundos después de que h3 deje de enviar NA, la situación se corrige sola: NUD lleva la entrada a `STALE` y, al usarla, h1 envía un NS de comprobación al que responde **el verdadero h2**, que recupera su sitio en la caché. El desvío solo se mantiene mientras el emisor insiste.

En una red real esto se evita en el switch de acceso con **ND Inspection / Source Guard**: el switch aprende qué dirección IPv6 corresponde a cada puerto (observando DAD y DHCPv6) y descarta los NA que anuncian una dirección por un puerto que no es el suyo. **RA Guard** hace lo propio con los RA. Y ten en cuenta la regla del Hop Limit 255: por eso esto solo puede hacerse desde dentro de la LAN, nunca a través de un router.
