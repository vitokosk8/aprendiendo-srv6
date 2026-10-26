# E6 · Soluciones

Vuelve a la [práctica](practica.md) o al [escenario](README.md).

## Parte A

**A1.** Con funciones que entienden SRv6: `5f00:0:3:a1::`, `5f00:0:4:f1::` y el SID de servicio de r6, en ese orden. El IDS y el firewall procesan su segmento y pasan al siguiente, como un `End`. En este laboratorio, el firewall no entiende SRv6, y la lista de r1 termina en el SID del proxy: `5f00:0:3:a1::`, `5f00:0:4:f1::`. El SID de r6 no lo pone r1, sino r4, al reencapsular lo que vuelve del firewall.

**A2.** Porque es la **interfaz por la que vuelve el paquete** lo que le dice a r4 que ya ha pasado por el firewall y hacia dónde reencapsularlo. Con una sola VRF, el paquete que sale del firewall hacia BLUE-2 buscaría `192.168.20.12` en la misma tabla en la que la estática lo manda al firewall, y **volvería a entrar en él**: un bucle hasta que se agote el TTL.

**A3.** Las respuestas de h2 vuelven **directas** de r6 a r1, con el SID de r1, sin pasar por el firewall. El ping funcionaría (el firewall de este laboratorio no tiene estado). Pero un firewall **con estado** solo vería los paquetes de un sentido: para él, la conexión TCP nunca se completa, y la bloquearía o la dejaría a medias según su política. Por eso la cadena se monta en los dos sentidos.

**A4.** Que el proxy solo recuerda **una** cabecera por función. Si llegan paquetes de dos cadenas distintas, cada uno sobrescribe la cabecera del anterior, y los que salen del firewall se reencapsulan con la cadena del otro cliente. Por eso un proxy dinámico necesita una instancia (o al menos una interfaz o VLAN) por cada cadena distinta.

## Parte C

**C1.** En **FW1**, la estática `192.168.20.0/24 via 172.16.41.2` lleva al firewall, y `192.168.10.0/24` reencapsula hacia el SID de r1. En **FW2**, al revés: `192.168.10.0/24` va al firewall por `172.16.42.2`, y `192.168.20.0/24` reencapsula hacia r6. Las que reencapsulan son rutas **BGP**: las VRF del proxy importan el RT `64500:10`, así que aprenden las rutas de BLUE con su SID, como cualquier PE. Para la sede del otro lado, la ruta BGP también existe, pero pierde contra la estática (distancia 200 frente a 1).

**C2.** El tráfico **sí pasa por r4** (es el camino más corto: r1 → r2 → r4 → r6), pero como tránsito: va hacia el SID de r6 y r4 lo reenvía por la ruta del locator de r6. **No** pasa por el firewall: los contadores siguen a cero.

**C3.** Está abierto: sin cadena, nada filtra el tráfico entre sedes.

## Parte D

**D1.** r1 encapsula hacia **`5f00:0:4:f1::`**, con un solo segmento. El camino entre r1 y r4 **no cambia** (r1 → r2 → r4, el más corto hacia el locator de r4). Lo que cambia es **dónde termina** el primer tramo: en r4, no en r6.

**D2.** Ahora los contadores del firewall suben con cada ping, y el telnet **no** conecta (se queda esperando hasta el `timeout`). El puerto 80 sigue funcionando: la política solo bloquea el 23.

**D3.**

| Captura | Destino | Tipo |
|---|---|---|
| r2 `eth3` | `5f00:0:4:f1::` | IPv6 (con el IPv4 de h1 dentro) |
| fw `eth1` | `192.168.20.12` | **IPv4** |
| fw `eth2` | `192.168.20.12` | **IPv4** |
| r6 `eth1` | el SID de r6 (`5f00:0:6:…`) | IPv6 |

El destino IPv6 cambia **en r4**, y no porque r4 modifique el paquete que le llegó: lo desencapsula, lo entrega al firewall y, cuando vuelve, **construye uno nuevo** con la ruta BGP de FW2. El paquete que llega a r6 es de r4.

**D4.** El SYN aparece en **`fw eth1`** (entra al firewall) y **no** en `fw eth2`: la regla de iptables lo descarta dentro del firewall.

**D5.** El ping **funciona**, pero en `fw eth2` solo ves las peticiones, no las respuestas: vuelven directas de r6 a r1. Es la asimetría de A3: este firewall no tiene estado y no le importa, pero uno real sí.

## Parte E

**E1.** **No funciona.** Y en el plano de control todo está bien: la sesión BGP está establecida, la ruta de BLUE-2 en r1 apunta al SID del proxy y r4 tiene sus dos `End.DT4`. Nada avisa de que la función de servicio no reenvía.

**E2.** El paquete llega a r2, a r4 y entra en el firewall (`fw eth1`), pero **no sale** por `fw eth2`. El fallo está dentro de la función de servicio.

**E3.** Si el firewall no se pudiera arreglar, la solución rápida sería **quitar las estáticas** de r1 y r6: el tráfico volvería a ir directo por la L3VPN, **sin filtrar**. Es una decisión del cliente, no del operador: muchos departamentos de seguridad prefieren perder la comunicación (*fail-closed*) a dejarla pasar sin firewall (*fail-open*). En producción esto se decide de antemano y se automatiza: el proxy vigila la función y, según lo acordado, retira la ruta o la desvía a otra instancia.

**E4.** Sin las estáticas, r1 y r6 vuelven a la ruta BGP, con el SID del otro PE, y `verificar.sh` vuelve a dar todo en verde.
