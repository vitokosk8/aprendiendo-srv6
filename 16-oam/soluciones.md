# 16 · Soluciones

> Las salidas son orientativas; los valores de función de los SIDs automáticos (End/End.X) los asigna FRR y variarán. El servicio `End.DX4` sí es fijo (`5f00:0:X:dc04::`).

## Parte A

**A1.** Porque en SRv6 **un SID es una dirección IPv6** y el transporte es IPv6 normal: `ping`/`traceroute` (ICMPv6) y `tcpdump` funcionan sin extensiones. Ventaja operativa: usas las herramientas de siempre, y los nodos que no "entienden" SRv6 igualmente reenvían y responden ICMP.

**A2.** Confirma que el SID **está instalado localmente** en ese nodo (lo procesa y responde). **No** confirma que su *behavior* haga lo correcto (p. ej., pingar un `End.X` no prueba que el paquete salga por la interfaz/vecino correctos; para eso hay que usarlo como SID de tránsito en una lista).

**A3.** Con SRH: `ip6[6]==43` (Next Header = 43, Routing Header). IPv4 encapsulado sin SRH: `ip6[6]==4`. (IPv6 interior sin SRH: `ip6[6]==41`.)

**A4.** Cuando un endpoint procesa el **flag O**, hace una **copia** del paquete, le pone una marca de tiempo lo antes posible y la **punta** a un proceso OAM local (para exportar telemetría), sin tocar el paquete original. En Linux/FRR **no** está disponible de forma general (es de plataformas de operador).

**A5.** (Ejemplos; ver el catálogo de la teoría.)
- `seg6_enabled` desactivado → `sysctl net.ipv6.conf.<if>.seg6_enabled`.
- Locator no aprendido → `ip -6 route show <locator>` / `show isis segment-routing srv6 node`.
- `End.DT4` sin instalar por `strict_mode` → `sysctl net.vrf.strict_mode` y mirar `ip -6 route show | grep End.DT`.

## Parte B

### B1
1. El **loopback** de r3 (`3fff:0:ff::3`) responde (alcanzabilidad normal). El `End.DX4` (`5f00:0:3:dc04::`) **no** responde: es un behavior de *desencapsular + cross-connect*, que espera un paquete **encapsulado** con un IPv4 dentro; un echo suelto no es eso, así que no hay respuesta. Para confirmar que está instalado se **inspecciona**: `ip -6 route show 5f00:0:3:dc04::` (debe mostrar `seg6local action End.DX4`).
2. El SID inexistente (`5f00:0:3:ffff::`) cae dentro del locator de r3 (`5f00:0:3::/48`), así que el paquete **llega a r3**, pero r3 no tiene ese SID instalado → lo **descarta** (timeout).
3. Moraleja: el ping confirma alcanzabilidad y SIDs de tipo **End**/direcciones; los SIDs de **decap** (End.DX4/DT*) se verifican **inspeccionando** el plano de datos, no pingándolos.

### B2
1. Entre routers, el traceroute muestra los saltos intermedios (r1→r2→r3), cada uno devolviendo *Time Exceeded* desde la interfaz por la que entró el sondeo.
2. El traceroute del **cliente** puede ver menos saltos porque su tráfico va **encapsulado**: en el núcleo, el *hop-limit* que se decrementa es el **exterior**, no el del paquete del cliente; según cómo se copie el hop-limit al encapsular, los saltos del núcleo pueden quedar "ocultos" para el cliente. El del **transporte** (r1→loopback de r3) va sin encapsular y muestra los saltos normales.

### B3
1. Con un solo SID de servicio y `encap.red`, **no hay SRH**: el Next Header es **4** (IPv4 encapsulado directamente), porque el camino hasta el locator de r3 lo resuelve el IGP sin SIDs de tránsito. Verías 43 (SRH) si la lista tuviera más de un segmento.
2. El destino exterior es el `End.DX4` de r3 (`5f00:0:3:dc04::`).
3. Dentro va el **IPv4 del cliente** (`10.0.1.10 → 10.0.2.20`).

### B4
1. Sí, r1 aprende `5f00:0:3::/48` por IS-IS, por la interfaz hacia r2 (`eth2`).
2. En r3: el `End` del locator y los `End.X` de adyacencia (automáticos, en `sr0`) **más** el `End.DX4` manual (`5f00:0:3:dc04::`, servicio).
3. Sí: `ip route get 10.0.2.20` muestra el `encap seg6` hacia `5f00:0:3:dc04::`.

### B5
1. En esta topología lineal, r2 solo **reenvía** el IPv6 exterior (no procesa ninguna SRH porque el único SID es el de servicio en r3), así que desactivar `seg6_enabled` en r2 puede **no** romper este tráfico concreto. Para notarlo, fuerza un SID de **tránsito** en r2 (una lista `[<SID-de-r2>, 5f00:0:3:dc04::]`): entonces r2 sí tiene que procesar la SRH, y con `seg6_enabled=0` la descartaría. Es la lección: `seg6_enabled` importa en el nodo que **procesa** un SID, no en el que solo reenvía.
2. (Se restaura con `seg6_enabled=1`.)

### B6
1. El fallo está en el **servicio** (el SID de entrega en el PE de destino), no en el transporte ni en el encaminamiento del headend.
2. `ip -6 route show 5f00:0:3:dc04::/128` en r3: ya **no existe** la entrada `seg6local End.DX4`. (Mientras que en r1 `ip route get 10.0.2.20` sigue mostrando el encap hacia ese SID: el headend está bien; falla el extremo.)
3. (Se restaura añadiendo de nuevo el `End.DX4` en r3.)

### Reto
1. Capturando en cada tramo (`ip6[6]==43 -vv`) ves la SRH con su `segleft` y la lista `[0]…[n]`; el SID **activo** es el del destino exterior en cada salto, y `segleft` te dice cuántos quedan. Así reconstruyes el camino salto a salto.
2. Chuleta (una línea por fallo): `sysctl net.ipv6.conf.<if>.seg6_enabled` · `ip -6 route show <locator>` · `ip -6 route get <base-locator>` (¿`local`/`anycast`?) · `sysctl net.vrf.strict_mode` + `ip -6 route show | grep End.DT` · `ip route show <prefijo>` (¿está la ruta encap?) · `vtysh -c "show isis neighbor"` · `ping -M do -s <grande>`.
3. Porque, al ser el SID una **dirección IPv6 enrutable**, el diagnóstico se reduce casi siempre a dos preguntas encadenadas: (a) ¿el núcleo **enruta** hacia esa dirección? (transporte, IS-IS) y (b) ¿el nodo dueño tiene el SID **instalado** y con el behavior correcto? (`seg6local`). Si ambas son "sí", el paquete llega y se procesa; casi todo fallo es una de las dos en "no".
