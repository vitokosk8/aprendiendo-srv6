# 13 · Soluciones

> Las salidas son orientativas; los valores de función de los SIDs los asigna FRR y variarán entre despliegues.

## Parte A

**A1.** Dos estrategias:
- **Por familia** (`sid vpn export` en cada `address-family`): produce **dos** SIDs, un **`End.DT4`** (IPv4) y un **`End.DT6`** (IPv6).
- **Por VRF** (`sid vpn per-vrf export`): produce **un** SID **`End.DT46`**, que sirve para ambas familias.

**A2.** Un `End.DT46` **desencapsula** el paquete SRv6 y busca el destino interior en la tabla de la VRF, **según la versión del paquete interior**: si lo que queda tras quitar la cabecera exterior es IPv4, busca en la tabla IPv4 de la VRF; si es IPv6, en la IPv6. La familia la decide mirando el paquete que había dentro, no el SID.

**A3.** El IPv6 del cliente viaja **dentro de un paquete IPv6 del núcleo** (IPv6-en-IPv6): la cabecera exterior va hacia el `End.DT46` del PE de destino. r2 **no** ve el IPv6 del cliente; solo ve el IPv6 **exterior** (destino = un SID del locator de r3) y lo reenvía como cualquier IPv6, sin enterarse de lo que lleva dentro.

**A4.** Con `sid vpn per-vrf export`: **un** SID (`End.DT46`). Con `sid vpn export` en cada familia: **dos** (un `End.DT4` y un `End.DT6`).

**A5.** **Se mantiene igual** todo el modelo del módulo 12: CE/PE/P, la VRF, el RD (hace únicas las rutas), el RT (decide importaciones), `strict_mode`, y el transporte IS-IS+SRv6. **Cambia** solo: se añade la familia **IPv6** (direcciones de cliente IPv6, `address-family ipv6 unicast` en la VRF y `address-family ipv6 vpn` global) y el SID pasa a `End.DT46` (o se añade un `End.DT6`).

## Parte B

### B1
1. **Uno**: un `End.DT46` (porque usamos `sid vpn per-vrf export`):
   ```
   5f00:0:3:...::  encap seg6local action End.DT46 vrftable 10 dev CUST proto bgp
   ```
2. Actúa sobre `vrftable 10` (la tabla de la VRF CUST) y está instalado en el dispositivo de la VRF (`dev CUST`).

### B2
1. Sí: `show bgp ipv4 vpn` muestra `10.0.2.0/24` y `show bgp ipv6 vpn` muestra `2001:db8:2::/64`, ambas aprendidas de r3 (RD `10.0.0.3:101`, RT `65000:101`).
2. Llevan el **mismo** SID `End.DT46` de r3: un único SID de servicio sirve para las dos familias.

### B3
1. En la VRF: en IPv4, la local `10.0.1.0/24` y la remota `10.0.2.0/24`; en IPv6, la local `2001:db8:1::/64` y la remota `2001:db8:2::/64`.
2. Sí: la ruta IPv6 a `2001:db8:2::/64` se entrega con un **encap SRv6** hacia el `End.DT46` de r3 (el mismo SID que la ruta IPv4).

### B4
1. El destino IPv6 exterior es el **`End.DT46` de r3** (dentro de `5f00:0:3::/48`).
2. r2 **no distingue** el IPv6 del cliente: solo ve el IPv6 **exterior** (hacia el SID de r3) y lo reenvía. El IPv6 interior (`2001:db8:1::10 → 2001:db8:2::20`) es carga opaca para él.
3. **r3**, con su **`End.DT46`**: desencapsula, ve que el interior es IPv6 y lo busca en la tabla IPv6 de la VRF, entregándolo a h2.

### B5
1. Ahora hay **dos** SIDs en r3: un `End.DT4` y un `End.DT6` separados.
2. El ping dual-stack sigue funcionando: cada familia usa su SID.
3. **SIDs separados**: permiten políticas distintas por familia (y distinguir v4/v6 ya en el SID). **End.DT46 único**: más simple y compacto (una sola función por VRF), ideal para dual-stack corriente. (Ver la tabla de la teoría.)
4. (Se vuelve al per-vrf con los comandos indicados.)

### Reto
1. `show bgp ipv6 vpn 2001:db8:2::/64` muestra el *Remote SID* = el `End.DT46` de r3; coincide con el que aparece instalado en r3 (`seg6local action End.DT46`).
2. Sí: un núcleo que solo transporta IPv6 basta para cualquier servicio, porque el servicio va **codificado en el SID** y solo lo entienden los PE. Añadir EVPN/L2 (End.DX2/DT2) o más VPNs no toca el núcleo: el modelo **transporte (IGP) + servicio (BGP)** desacopla ambos planos, así que crecer en servicios no afecta a los P.
3. Porque el núcleo es **IPv6 puro** y los PE se alcanzan por su **loopback IPv6**; el SID de servicio también es una dirección IPv6. Usar un next-hop IPv6 (con *extended-nexthop*) para las rutas IPv4-VPN e IPv6-VPN unifica todo sobre el mismo plano IPv6: una sola sesión BGP y un solo tipo de transporte para ambas familias de cliente.
