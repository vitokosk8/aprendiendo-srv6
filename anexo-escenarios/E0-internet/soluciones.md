# E0 · Soluciones

Algunas respuestas dependen de valores que asigna FRR al arrancar (los SIDs `auto`, las direcciones *link-local*). Donde aparece `5f00:0:6:…`, el valor exacto es el que veas en tu laboratorio.

## Parte A

**A1.** La miran **h1**, **r1** (para decidir que va hacia r6 y encapsular), **r6** (al desencapsular, para buscar el destino en su tabla), el upstream y el servidor. **r2 y r4 no la ven nunca**: para ellos el paquete es un paquete IPv6 con destino `5f00:0:6:…`, y solo miran la cabecera exterior. Ni siquiera necesitan entender IPv4.

**A2.** r1 recibiría la ruta con siguiente salto `192.0.2.1`, una dirección que no conoce (no está en IS-IS). BGP marcaría la ruta como **inválida** y no la instalaría. `next-hop-self` cambia el siguiente salto por la dirección de r6, que r1 sí alcanza.

**A3.** **No.** Es la gracia del diseño: el nuevo cliente solo implica configuración en r1 (y, si tiene su propio bloque, que BGP lo anuncie). Los P siguen sin conocer ninguna ruta de cliente ni de Internet.

**A4.** Porque en r6 la opción `encapsulation-srv6` solo está activada hacia r1. El upstream es otro operador: no forma parte del dominio SRv6, no sabría qué hacer con un SID de r6 y, por seguridad, nunca debe poder enviar tráfico a los SIDs internos (módulo 18).

## Parte B

**B1.** Sale por `eth1` (hacia r2, el camino más corto hacia r6) con `encap seg6 mode encap segs 1 [ 5f00:0:6:… ]`. Ese SID está dentro de `5f00:0:6::/48`, el locator de **r6**: es su `End.DT46` de la VRF INTERNET.

**B2.** **No está.** Las rutas de Internet viven solo en la VRF INTERNET. El tráfico que genera el propio r1 (por ejemplo, un ping desde su loopback) usa la tabla principal, así que **r1 no llega a Internet** salvo que lo haga desde la VRF (`ping -I INTERNET …`). Para un operador puede ser una ventaja (la red de gestión queda aislada de Internet) o un inconveniente, según lo que quiera.

**B3.** r2 no tiene ninguna ruta a `198.51.100.0/24`. Reenvía el tráfico del cliente con su ruta IS-IS a `5f00:0:6::/48`, el locator de r6, por `eth3` hacia r4.

**B4.** `vrftable 10`: la tabla de la VRF INTERNET. El paquete desencapsulado se busca en la tabla de Internet de r6, que sabe llegar a `198.51.100.0/24` por el upstream.

**B5.** Normalmente verás **r1**, **r6**, el **upstream** y el **servidor**, pero **no r2 ni r4**. El *traceroute* juega con el TTL del paquete IPv4 interior, y los P no lo tocan: solo decrementan el *hop limit* de la cabecera IPv6 exterior. Para el cliente, todo el núcleo del operador es un único salto. Es lo mismo que pasa con MPLS cuando el operador no propaga el TTL.

## Parte C

**C1.** La ruta está en la **tabla principal** (sin `vrf`). En `vtysh` aparece como ruta BGP con `seg6` y el SID de r6; en el kernel, con el mismo `encap seg6 … segs 1 [ 5f00:0:6:… ]`. Es **igual** el camino (por `eth1`, hacia r2) y la idea de encapsular hacia un `End.DT46` de r6. **Cambia** que no hay VRF, ni RD ni RT, y que la ruta viene de la familia IPv4 *unicast*, no de VPNv4.

**C2.** En el detalle de la ruta BGP verás el SID de r6 (en la línea de *SID* o *Remote SID*), el siguiente salto `3fff:0:ff::6` (por `next-hop-self`) y el AS del upstream en el *AS path* (`64496`).

**C3.** r6 tiene **un** SID de servicio, el `End.DT46` (además de su `End` y sus `End.X` de transporte), que sirve para IPv4 e IPv6. `vrfdefault` no tiene interfaces porque no es para meter tráfico de clientes: solo existe para que el kernel tenga una **VRF ligada a la tabla principal (254)**, que es donde el `End.DT46` necesita entregar el paquete desencapsulado.

**C4.** **No.** El upstream recibe la ruta normal, con el AS path `64500` y siguiente salto `192.0.2.2`. r6 no tiene `encapsulation-srv6` hacia el upstream, así que no le envía el atributo SRv6. Fuera del dominio del operador, SRv6 no existe.

## Parte D

**D1.** **Nada** (o casi nada): el camino más corto de r1 a r6 es r1 → r2 → r4 → r6, y r3 no está en él.

**D2.** Queda seleccionada la **estática**. Tiene distancia administrativa **1**, y la ruta iBGP **200**: gana la de menor distancia. La ruta de BGP sigue existiendo, pero no seleccionada.

**D3.** El destino es **`5f00:0:5::`**, el `End` de r5, y el SRH lleva **dos** segmentos: el de r5 y el `End.DT46` de r6. r3 no hace nada especial: reenvía hacia el locator de r5 como cualquier router.

**D4.** En r4 (`eth1`, desde r2) **no** ves la ida, que ahora va por r3 y r5. Pero **sí** ves la vuelta: el servidor responde a h1, y r6 encapsula la respuesta hacia el `End.DT46` de r1 por el camino más corto, r6 → r4 → r2 → r1. La ruta TE solo cambia la ida: el tráfico es **asimétrico**. Si quisieras también la vuelta por abajo, necesitarías otra ruta TE en r6.

**D5.** Con `no ip route 198.51.100.0/24 3fff:0:13::3 eth2 segments 5f00:0:5::/SID`, la estática desaparece y vuelve a seleccionarse la de BGP (`segs 1`, por `eth1`).

## Parte E

**E1.** Deja de funcionar **IPv4**. IPv6 puede seguir funcionando, o fallar un momento mientras FRR reasigna su SID: compruébalo en tu laboratorio y explica lo que ves con E2.

**E2.** El camino de diagnóstico:

1. En r1, `show bgp ipv4 unicast`: la ruta a `198.51.100.0/24` ha **desaparecido**. El problema está en el plano de control, no en el núcleo.
2. ¿Por qué no llega? Porque r6 solo envía a r1 rutas con SID (`encapsulation-srv6`), y en IPv4 ya no hay SID que poner. En r6, `show bgp segment-routing srv6`: en la tabla global, el SID de IPv4 (`srv6_unicast[AFI_IP].sid`) está vacío.
3. En r6, `ip -6 route show | grep seg6local`: puedes ver que el `End.DT46` ha desaparecido o ha cambiado (por ejemplo, a un `End.DT6` solo para IPv6), porque ya no lo comparten las dos familias.

Es un fallo típico del catálogo del módulo 17, "el servicio no tiene SID", visto desde la tabla global.

**E3.** Vuelve a añadir el SID en la familia IPv4 de r6:

```
r6(config)# router bgp 64500
r6(config-router)# address-family ipv4 unicast
r6(config-router-af)# sid export auto behavior dt46
```

Si el `End.DT46` no reaparece en el kernel de r6, quítalo y vuelve a ponerlo también en la familia IPv6, para que las dos familias vuelvan a compartirlo. Después, `./verificar.sh` debe salir en verde.
