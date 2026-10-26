# E2 · Soluciones

Algunas respuestas dependen de valores que asigna FRR al arrancar (los SIDs `auto`). Donde aparece `5f00:1:8:…`, el valor exacto es el que veas en tu laboratorio.

## Parte A

**A1.** Opción A: **50 VRF** y **50 sesiones eBGP** en cada ASBR (una por cliente), y cada cliente nuevo exige configurar los dos ASBR. Opción C: **ninguna VRF** y **una sola sesión eBGP** en cada ASBR, la de los bloques. Los clientes nuevos solo se configuran en los PE.

**A2.** Dos rutas: `5f00:1::/32` (todos los SIDs del AS 64501) y `3fff:1:ff::/48` (todas sus loopbacks). **Siguen siendo dos** con 200 PE: los locators de esos PE están todos dentro del bloque.

**A3.** En la opción A, cada operador solo importa rutas de su propia VPN: las del otro le llegan como rutas IPv4 de un "cliente", sin RT. En la opción C, la ruta VPNv4 que exporta r8 llega tal cual a r1, con el RT que puso r8. Si r1 no importa ese RT, la ignora. Por eso tienen que acordar los RT (o traducirlos en el PE).

**A4.** r6 aprendería `5f00::/16` y lo redistribuiría en el IS-IS del AS 64500. El tráfico hacia **cualquier** SID que no esté en una ruta más específica (por ejemplo, de un tercer operador, o un SID mal escrito) iría hacia el AS 64501. Además, se rompe la idea de que el AS 64500 solo acepta el bloque acordado. Se evita con un **filtro de entrada** en la sesión eBGP de r6: un `prefix-list` que acepte solo `5f00:1::/32` y `3fff:1:ff::/48` (y un límite de prefijos).

## Parte B · Opción A

**B1.** `192.168.40.0/24` la aprende de **r7**, por la sesión eBGP de la VRF (`via 172.16.67.2`, sin encapsular). `192.168.10.0/24` la aprende de **r1**, por iBGP VPNv4, con encapsulado SRv6 hacia el `End.DT4` de r1. Solo la segunda va en SRv6.

**B2.** Hacia el `End.DT4` de **r6** (`5f00:0:6:…`), su propio ASBR. r1 no sabe nada del AS 64501.

**B3.** Paquetes **IPv4** normales, `192.168.10.12 ↔ 192.168.40.12`. El SRv6 del AS 64500 termina en r6.

**B4.** `64501`: la ruta viene del AS 64501, a través de la sesión eBGP entre los ASBR.

## Parte C · Opción C

**C1.** r6 anuncia `5f00:0::/32` y `3fff:0:ff::/48`, y r7 anuncia `5f00:1::/32` y `3fff:1:ff::/48`. **Ninguna ruta de cliente**: los ASBR no participan en la VPN. En la configuración de IS-IS de r6 aparece `redistribute ipv6 bgp level-2`.

**C2.** Dos rutas, aprendidas por **IS-IS** como rutas externas (r6 las redistribuye desde BGP). r3 no ejecuta BGP.

**C3.** r1 habla con **r8** (`3fff:1:ff::8`), el PE del otro AS, por eBGP multisalto. Encapsula hacia el `End.DT4` de **r8** (`5f00:1:8:…`).

**C4.** Ahora pasan paquetes **IPv6** con destino `5f00:1:8:…` y, dentro, el IPv4 del cliente. En la opción A el enlace veía IPv4 del cliente; aquí, un túnel SRv6 que lo atraviesa.

**C5.** Normalmente verás r1, r8 y h4, pero **no** los P ni los ASBR: dentro del túnel, el TTL del IPv4 interior no cambia. Para el cliente, los dos operadores son un único salto.

## Parte D

**D1.** `5f00:0:5::` (el `End` de r5) es del **AS 64500**; el SID de r8 es del **AS 64501**.

**D2.** En r3, el destino es `5f00:0:5::`: el paquete va hacia el primer segmento. En r6 (`eth6`), el destino ya es el SID de r8: r5 ejecutó su `End`, avanzó al siguiente segmento y lo puso como destino.

**D3.** **No**: en la opción A, r1 no conoce ningún SID del AS 64501, ni tiene ruta hacia su bloque. Solo puede controlar el camino hasta su propio ASBR.

**D4.** Con `no ip route …` (los mismos parámetros, dentro de `vrf BLUE`), la estática desaparece y vuelve la ruta de BGP, con un solo segmento.

## Parte E

**E1.** No funciona en ningún sentido. De h1 a h4, el ping llega a h4 (r1 sigue sabiendo llegar a `5f00:1::/32`), pero la **respuesta** no vuelve: r8 encapsula hacia el SID de r1, `5f00:0:1:…`, y ya no tiene ruta hacia `5f00:0::/32`.

**E2.** En r8: `ping 3fff:0:ff::1` falla, e `ip -6 route show 5f00:0::/32` está vacío. Mientras tanto, r7 sigue teniendo la ruta en BGP (`show bgp ipv6 unicast`), pero ya no la mete en IS-IS. La sesión VPNv4 de r8 con r1 aguanta hasta que vence su *hold time*: después cae, y las rutas de las sedes desaparecen en los dos PE. El fallo está en el **transporte entre operadores**, no en el servicio.

**E3.** En r7:

```
r7(config)# router isis CORE
r7(config-router)# redistribute ipv6 bgp level-2
```

La sesión VPNv4 vuelve a establecerse sola (puede tardar algo, porque BGP espera antes de reintentar) y `./verificar.sh` debe salir en verde.
