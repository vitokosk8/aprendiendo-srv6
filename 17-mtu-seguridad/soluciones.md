# 17 · Soluciones

> Las salidas son orientativas.

## Parte A

**A1.** Con encap reducido y un solo SID: **40 bytes** (solo la cabecera IPv6 exterior; no hay SRH). Con 3 SIDs: 40 (IPv6 exterior) + 8 (SRH) + 16×3 = **96 bytes** (reducido: el primer SID va en el destino, pero la SRH lleva igualmente la lista; según implementación, 40 + 8 + 16×(n) o 16×(n−1); el orden de magnitud es ~90-96 bytes).

**A2.** Cliente máximo sin fragmentar = **MTU − encap = 1500 − 40 = 1460 bytes** de paquete de cliente. Uno mayor con el bit **DF** no puede reenviarse: el router genera **ICMPv6 Packet Too Big** y el paquete se descarta (no se fragmenta).

**A3.** Un *PMTUD blackhole* ocurre cuando los paquetes grandes con DF se descartan **pero** el **ICMPv6 Packet Too Big** que avisaría al origen **se pierde** (típicamente porque un firewall **bloquea ICMPv6** por error). El origen nunca se entera de que debe reducir el tamaño, así que el flujo se "cuelga": pings pequeños y handshakes van, pero las transferencias grandes mueren sin explicación.

**A4.** Porque si el SID es una **dirección IPv6 enrutable**, **cualquiera que logre enviarle un paquete puede activar su behavior** (inyectar en una VPN con un `End.DT4`, forzar caminos con un `End.X`, etc.). El modelo de SRv6 es un **SR domain de confianza**: dentro se usan los SIDs libremente, y el **borde DEBE filtrar** para que nada externo alcance esos SIDs.

**A5.** El borde debe **descartar todo tráfico entrante desde fuera** (clientes, Internet) cuyo destino —o cuya SRH— apunte al **bloque de SIDs del operador** (p. ej. `5f00::/16`), en **todas las interfaces externas/de cliente**. Conviene además usar un bloque **no anunciado a Internet** para que, desde fuera, ni siquiera sea enrutable hacia ti (defensa en profundidad): el filtro protege aunque alguien consiga enrutar hacia el bloque.

## Parte B

### B1
1. `-s 1400` pasa (1400 + 28 de cabeceras IPv4/ICMP = 1428 de cliente; + 40 de encap = 1468 < 1500). `-s 1440` con `-M do` falla (1440 + 28 = 1468; + 40 = 1508 > 1500).
2. El fragmentable (`-s 1440` sin `-M do`) **también falla**: en IPv6 los routers **en tránsito no fragmentan**, y el paquete exterior (que origina el PE) ya supera la MTU del núcleo. Por eso no se puede "arreglar fragmentando": la solución correcta es **dimensionar la MTU** del núcleo (B2). Es una diferencia clave respecto a IPv4, donde un router intermedio sí podía fragmentar.

### B2
1. Sí: con MTU 9000 en el núcleo, el paquete de ~1508 cabe de sobra, así que el `-M do -s 1440` pasa.
2. Regla de oro: **MTU del núcleo ≥ MTU del cliente + sobrecarga máxima de SRv6** (dimensiona para la lista de segmentos más larga que vayas a usar). En la práctica, jumbo frames (9000+) en todo el core.
3. (Al volver a 1500, el `-M do -s 1440` vuelve a fallar.)

### B3
1. **No llega**: el PE (r1) tiene una regla `ip -6 rule ... from 3fff:0:1::/64 to 5f00::/16 blackhole` que **descarta** en el borde todo lo que el cliente (su prefijo de origen) manda hacia los SIDs internos. `ip -6 rule show | grep 5f00` la muestra. (Se acota por origen del cliente, no por `iif`, para no descartar el tráfico que el propio PE encapsula hacia un SID, que sale con tunsrc del PE.)
2. Sí, el servicio legítimo (`10.0.2.20`) sigue: ese tráfico va dirigido a una IPv4 de cliente, **no** a `5f00::/16`, así que la regla no lo toca (y el encap hacia el SID lo genera **el propio r1**, no entra por eth1).

### B4
1. Sin el filtro, el ping de h1 a `5f00:0:3::` **sí llega al núcleo** (r1 lo reenvía por IS-IS). Un atacante que pudiera mandar paquetes a tus SIDs de servicio podría intentar **inyectar tráfico en una VPN** (`End.DT4`/`DX4`), **forzar caminos** (`End.X`) o abusar de otros behaviors: es un agujero serio.
2. (Se restaura el filtro con el `ip -6 rule add ...`.)
3. Porque si `5f00::/16` **no se anuncia** a Internet, desde fuera no es siquiera enrutable hacia ti: un atacante remoto no puede hacer llegar un paquete a esas direcciones. Es una **segunda barrera** además del filtro de borde (defensa en profundidad); ninguna sustituye a la otra.

### Reto
1. Peligroso porque un paquete puede entrar con un **destino inocente** pero una **SRH** cuyos SIDs sean internos: al procesar el primer SID, el paquete entraría en el dominio con una lista de segmentos que tú no pusiste. Una ACL completa debe mirar **también** la SRH (no solo el destino), o directamente **descartar paquetes con SRH** entrantes desde el cliente, salvo los casos permitidos.
2. Política de borde: aplicar la ACL **inbound en todas las interfaces externas/de cliente** de cada PE; **filtrar el bloque completo de SIDs** del operador (destino y SRH); y poner esos enlaces (y el núcleo) con **MTU grande** para absorber la sobrecarga de SRv6. Complementar con bloque no anunciado y, donde cruce fronteras de confianza, HMAC en la SRH.
3. Los tres principios: (a) **el SID es una dirección IPv6** enrutable → tooling y reenvío estándar, pero hay que filtrar; (b) **el camino viaja en el paquete** (lista de segmentos) → TE y resiliencia sin estado por-flujo en el núcleo; (c) **el borde filtra y el núcleo confía** → el core se mantiene simple y seguro, y toda la inteligencia (servicios, políticas) vive en los PE.
