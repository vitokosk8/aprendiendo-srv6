# 12 · Soluciones

> Las salidas de comandos son orientativas. Los valores de función de los SIDs (`End.DT4`) los asigna FRR, así que las direcciones concretas variarán entre despliegues.

## Parte A

**A1.**
- **CE** (*Customer Edge*): el equipo del cliente → **h1** y **h2**.
- **PE** (*Provider Edge*): el router del operador donde se conecta el cliente; aloja la VRF → **r1** y **r3**.
- **P** (*Provider*): router del núcleo que solo transporta → **r2**.
- **VRF**: tabla de rutas aislada por cliente dentro del PE.

**A2.**
- **RD** (*Route Distinguisher*): hace **únicas** las rutas al viajar por BGP (antepone un valor al prefijo), para que dos clientes con las mismas IPs no se confundan. **No** decide importaciones.
- **RT** (*Route Target*): **etiqueta** que decide **en qué VRFs entra** la ruta (quién la importa). Es quien construye la topología de la VPN.

**A3.** El **`End.DT4`**: desencapsula el paquete SRv6 y **busca el destino IPv4 interior en la tabla de una VRF**. Necesita una VRF real (y no la tabla main) porque, como viste en el módulo 08, la implementación de Linux de End.DT4 exige `vrftable` apuntando a una VRF; aquí esa VRF **es** la del cliente.

**A4.** r2 (P): **no** tiene BGP, **no** tiene VRF, **no** sabe que existe la VPN. Es bueno para la escalabilidad porque añadir clientes o VPNs **no le afecta**: el núcleo se mantiene simple y estable, y toda la inteligencia de servicio vive en los PE.

**A5.** No chocan porque cada cliente vive en su **propia VRF** (tabla de rutas aislada) y sus rutas llevan **RD distinto** (las hace únicas en BGP) y **RT distinto** (entran solo en las VRFs de ese cliente). Tocarías solo los **PE** donde se conecta el cliente 2 (nueva VRF, nuevo End.DT4, nuevo RD/RT); **r2 no se toca**.

## Parte B

### B1
1. Sí: `show bgp ipv4 vpn summary` muestra el vecino `3fff:0:ff::3` en estado `Established`.
2. La capacidad **extended-nexthop** ([RFC 8950](https://www.rfc-editor.org/rfc/rfc8950)): permite anunciar rutas IPv4 con *next-hop* IPv6, de modo que la sesión iBGP va sobre los loopbacks IPv6 del núcleo aunque transporte prefijos IPv4 del cliente.

### B2
1. Sí: `10.0.2.0/24` aparece aprendida del otro PE, con su **RD** (`10.0.0.3:101`, el de r3) y el **RT** `65000:101` (el mismo que importa r1).
2. La ruta lleva un **SID End.DT4** dentro del locator de **r3** (`5f00:0:3:…::`) y *next-hop* el loopback de r3. Ese SID es el que r1 usará para encapsular hacia r3.

### B3
1. r3 ha asignado un `End.DT4` en su locator (p. ej. `5f00:0:3:<func>::`) que actúa sobre `vrftable 10` (la tabla de la VRF CUST):
   ```
   5f00:0:3:...::  encap seg6local action End.DT4 vrftable 10 dev ...
   ```
2. Lo creó **BGP** (al configurar `sid vpn export auto` en la VRF), no tú. En el módulo 11 el `End.DX4` lo pusiste a mano con `ip -6 route add`; aquí BGP lo asigna, lo instala y lo anuncia solo.

### B4
1. En la VRF CUST de r1 están: la red **local** `10.0.1.0/24` (conectada, del CE h1) y la red **remota** `10.0.2.0/24` (aprendida por BGP del PE r3).
2. La ruta a `10.0.2.0/24` se entrega con un **encap SRv6** hacia el `End.DT4` de r3: FRR programa el encapsulado automáticamente a partir del anuncio BGP.

### B5
1. r2 **no** tiene sesiones BGP, **no** tiene la VRF CUST y **no** tiene ningún `End.DT4`.
2. Aun así el tráfico de la VPN lo cruza porque r2 solo ve un **paquete IPv6** cuyo destino es un SID dentro del **locator de r3**; lo reenvía por IS-IS como cualquier IPv6, sin mirar (ni entender) lo que lleva dentro.
3. Implica que añadir clientes nuevos **no requiere tocar r2** (ni ningún P del núcleo). Toda la configuración de servicio vive en los PE. Eso es lo que hace escalar a SRv6.

### B6
1. El destino IPv6 del paquete en r2 es el **SID End.DT4 de r3** (dentro de `5f00:0:3::/48`).
2. Dentro viaja el **IPv4 privado del cliente** (de `10.0.1.10` a `10.0.2.20`). r2 **no lo entiende ni le hace falta**: para él es carga opaca de un paquete IPv6.
3. En el otro extremo, **r3** ejecuta el `End.DT4`: desencapsula y busca `10.0.2.20` en la tabla de la VRF (tabla 10), entregándolo a h2.

### Reto
1. No colisiona porque cada cliente tiene su **VRF** (tabla aislada): el `10.0.2.0/24` de CUST y el de CUST2 son entradas en tablas distintas, con **SIDs End.DT4 distintos** (uno por VRF). En el núcleo nunca se ven como IPv4; van dentro de SRv6 hacia SIDs diferentes.
2. El **RD** (las hace únicas al viajar por BGP) y el **RT** (decide que entren solo en la VRF del cliente correcto).
3. **No** cambiaría nada en r2: sigue transportando IPv6 hacia los locators de los PE, ajeno a cuántas VPNs o clientes haya. Esa indiferencia del núcleo es justo lo que busca un operador: crecer en servicios sin tocar el core.
