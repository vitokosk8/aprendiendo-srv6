# 04 · Soluciones

> Las salidas de comandos son orientativas y se ajustarán con las de una ejecución real del laboratorio.

## Parte A

**A1.** Gana siempre el prefijo más largo que encaje:

1. `3fff:0:3::30` → encaja con `::/0`, `/48` y `/64`. Gana el **`/64` vía 3fff:0:23::2**.
2. `3fff:0:3:5::1` → encaja con `::/0`, `/48`, `/64` y `/80`. Gana el **`/80` vía 3fff:0:13::3**.
3. `3fff:0:3:abcd::1` → encaja con `::/0` y `/48` (no con el `/64`, que es `3fff:0:3:0::/64`). Gana el **`/48` vía 3fff:0:13::3**.
4. `3fff:0:9::1` → solo encaja con `::/0`. Gana la **ruta por defecto vía 3fff:0:12::2**.
5. La red `3fff:0:3::/64` como tal se corresponde con la entrada `/64`: **vía 3fff:0:23::2**.

**A2.** Con las dos a `metric 20`, usa **las dos a la vez** (ECMP) y reparte el tráfico por flujo. Con `metric 20` y `metric 100`, usa solo la de **métrica 20**; la de 100 queda como reserva.

**A3.** Ida h1→h2: h1 envía a su router r1; r1 tiene `3fff:0:2::/64 via 3fff:0:12::2`, así que va **r1→r2**; r2 entrega a h2. Camino: **h1 → r1 → r2 → h2**.
Vuelta h2→h1: h2 envía a r2; r2 tiene `3fff:0:1::/64 via 3fff:0:12::1`, así que **r2→r1**; r1 entrega a h1. Camino: **h2 → r2 → r1 → h1**. **Coinciden** (en sentido inverso), porque las rutas estáticas que configuramos son simétricas. No tendría por qué ser así (ver B6).

**A4.** Una ruta `blackhole` **existe** y encaja con el destino: el router la elige por LPM y descarta el paquete, normalmente **en silencio**. Si no hay ninguna ruta, el router no encuentra nada que encaje y envía al origen un **ICMPv6 Destination Unreachable (no route)**. En los dos casos el paquete no llega, pero en el primero el router "decide" descartarlo y en el segundo "no sabe" qué hacer con él.

**A5.** Lo reenvía por **`5f00:0:2::/48`**, porque es el prefijo más largo que encaja (`/48` gana a `::/0`). **No necesita entender SRv6**: para él es una dirección IPv6 cualquiera que cae dentro de un prefijo conocido. Esa es la idea central de SRv6: los routers de tránsito hacen IPv6 normal, y solo el dueño del locator ejecuta la instrucción del SID.

## Parte B

### B1

1. En r1 hay:
   - **3 conectadas** (`C>*`): `3fff:0:1::/64` (eth1), `3fff:0:12::/64` (eth2) y `3fff:0:13::/64` (eth3).
   - **3 estáticas** (`S>*`): `3fff:0:2::/64`, `3fff:0:3::/64` y `3fff:0:23::/64`.
   - Varias **locales** (`L>*`): las direcciones `/128` del propio router (las `::1` de cada interfaz) y `fe80::/64`.
2. `>` marca la ruta **seleccionada** (la mejor de su prefijo) y `*` que está **instalada en la FIB** (en uso para reenviar). Una ruta `>*` es la que el router usa de verdad.
3. La ruta conectada a la red de h1 es `C>* 3fff:0:1::/64 is directly connected, eth1`. No tiene siguiente salto porque esa red está **directamente conectada**: para llegar a cualquier dirección de `3fff:0:1::/64`, r1 no necesita un intermediario; la resuelve con Neighbor Discovery en eth1 y entrega directamente.

### B2

1. `3fff:0:3::30` sale por **`via 3fff:0:13::3, eth3`** (la estática hacia la red de h3, por r3). `3fff:0:2::20` sale por **`via 3fff:0:12::2, eth2`** (hacia la red de h2, por r2).
2. Tras añadir el `/128`:
   - `3fff:0:3::30` → ahora gana la ruta `/128` **vía 3fff:0:12::2** (por r2), porque es más específica que el `/64`.
   - `3fff:0:3::99` → sigue por el `/64` **vía 3fff:0:13::3** (por r3): el `/128` no le afecta.
3. El traceroute a `3fff:0:3::30` pasa ahora por **r2**: primero `3fff:0:12::2` (r1→r2) y luego `3fff:0:23::3` (r2→r3), antes de llegar a h3. h3 responde: hemos cambiado el camino de ida, no la conectividad. (La vuelta de h3 sigue yendo por r3→r1, así que el camino es asimétrico, pero el ping funciona.)

### B3

1. FRR ve **dos** rutas a `3fff:0:2::/64`: la de `metric 20` (vía r2) y la de `metric 200` (vía r3). Solo la de **métrica 20** está activa (`>*`), porque entre rutas del mismo prefijo gana la de menor métrica.
2. Al apagar eth2, la red conectada `3fff:0:12::/64` desaparece y con ella la posibilidad de alcanzar `3fff:0:12::2`. FRR retira la ruta de métrica 20 (su siguiente salto ya no es resoluble) e instala la de **métrica 200 vía 3fff:0:13::3**. El ping de h1 a h2 **sigue funcionando**, ahora por el camino r1→r3→r2.
3. Antes no se usaba porque su métrica (200) era peor que la de la ruta principal (20), y entre rutas del mismo prefijo solo la mejor baja a la FIB. Cuando la principal deja de ser válida, la de reserva pasa a ser la mejor disponible. Eso es el failover.

### B4

1. FRR muestra la ruta con **dos líneas de siguiente salto** bajo el mismo prefijo, las dos con `*`:

   ```
   S>* 3fff:0:3::/64 [1/0] via 3fff:0:13::3, eth3, weight 1
     *                     via 3fff:0:12::2, eth2, weight 1
   ```

   El kernel la muestra como una ruta **multipath** con varios `nexthop`:

   ```
   3fff:0:3::/64 metric 1024
       nexthop via 3fff:0:13::3 dev eth3 weight 1
       nexthop via 3fff:0:12::2 dev eth2 weight 1
   ```
2. Según el origen que le pongas, `ip -6 route get` resuelve unas veces por `3fff:0:13::3` y otras por `3fff:0:12::2`: el kernel elige el siguiente salto con un hash de las direcciones de origen y destino. Un único flujo siempre va por el mismo; flujos distintos pueden repartirse.
3. —

### B5

1. `ping` muestra `From 3fff:0:1::1 icmp_seq=1 Destination unreachable: No route`. Lo genera **r1**: no tiene ninguna ruta que encaje con `3fff:0:99::1` (ni por defecto), así que descarta el paquete y avisa a h1 con un ICMPv6 *Destination Unreachable*, código 0 (*no route to destination*).
2. Con la ruta por defecto, r1 **sí** reenvía el paquete a r3. Pero el ping sigue sin respuesta: r3 tampoco tiene ruta a `3fff:0:99::/64`, así que es **r3** quien ahora descarta y responde con *Destination Unreachable*. Aunque llegara a su destino, la **vuelta** tampoco tendría camino. Añadir una ruta por defecto en un solo router no crea conectividad si el destino no existe o si el camino de vuelta no está puesto.

### B6

1. Ida h1→h3: con la ruta `3fff:0:3::/64 via 3fff:0:12::2 10` (métrica 10, mejor que la 20 de la ruta por r3), r1 manda hacia **r2**, y r2 hacia r3. Camino: **h1 → r1 → r2 → r3 → h3**. Vuelta h3→h1: r3 usa `3fff:0:1::/64 via 3fff:0:13::1`, es decir, **r3 → r1** directo. Camino: **h3 → r3 → r1 → h1**.
2. **No coinciden**: la ida pasa por r2 y la vuelta no. Es enrutamiento asimétrico. El ping **funciona igual**: cada paquete se enruta por su cuenta y los dos extremos se alcanzan, aunque por caminos distintos.
3. —

### Reto

La ruta `blackhole` se añade con métrica 5, mejor que la 20 de la ruta normal a `3fff:0:3::/64`. Si le pusieras una métrica peor, la ruta normal seguiría ganando y el blackhole no haría nada: las dos tienen el mismo prefijo `/64`, así que compiten por métrica y solo la mejor baja a la FIB. Con métrica 5, la activa (`>*`) es el **blackhole**, y r1 **descarta en silencio** todo el tráfico hacia la red de h3.

El ping desde h1 se queda sin respuesta y, a diferencia de B5, **no recibe ningún mensaje de error**: una ruta blackhole descarta sin avisar. En B5, al no haber ninguna ruta, r1 sí respondía con *Destination Unreachable*. Es la diferencia entre "decido tirar este paquete" y "no sé qué hacer con él". (Una ruta `unreachable` en vez de `blackhole` sí enviaría el ICMPv6, por si quieres que el origen se entere.)
