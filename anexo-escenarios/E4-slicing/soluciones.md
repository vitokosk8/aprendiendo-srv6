# E4 · Soluciones

Vuelve a la [práctica](practica.md) o al [escenario](README.md).

## Parte A

**A1.**

| Pieza | En este laboratorio | Con Flex-Algo |
|---|---|---|
| Servicio | Una VRF por rebanada, con su RT | Igual: una VPN por rebanada |
| Topología | Estáticas con segmentos que fuerzan el paso por r4 o por r5 | Un algoritmo por rebanada, con su métrica y sus restricciones, calculado por IS-IS |
| Recursos | Ninguno: caminos disjuntos | Colas o canales dedicados (no es parte de Flex-Algo, pero se combinan) |
| Identificación | El SID de servicio, solo en los PE | El locator del algoritmo, en todos los routers (o un NRP ID en la cabecera) |

**A2.** **Un solo** segmento: el SID de servicio de PLATA en el locator del algoritmo 129 (`5f00:81:6:…`). Todos los routers tendrían la ruta hacia `5f00:81:6::/48` calculada **con la topología del algoritmo 129**, que no incluye los enlaces r2–r4 ni r4–r6. El paquete iría por abajo sin que r1 tenga que nombrar ningún nodo intermedio. Es la gran ventaja de Flex-Algo: la topología la pone la red, no la lista de segmentos.

**A3.** **No basta.** La topología decide por dónde va cada rebanada, pero si comparten un enlace, compiten por él. Haría falta **reservar recursos** en ese enlace: una cola con 2 Gb/s garantizados para ORO, o un canal FlexE. Y el router tiene que **clasificar** cada paquete: por el locator del SID de destino (si cada rebanada tiene el suyo), por un identificador de rebanada en la cabecera (*NRP ID*) o, en el peor caso, por el DSCP.

**A4.** En este laboratorio, PLATA se queda **sin servicio**: sus estáticas siguen apuntando a `5f00:0:5::` por r3, y r3 ya no puede llegar a r5 por el enlace directo. En realidad, IS-IS recalcularía y r3 llegaría a r5 por otro camino (r3 → r2 → r5, o r3 → r4 → r5). PLATA seguiría funcionando, pero **fuera de su topología**, por enlaces que no son suyos (según el recálculo, incluso por r2–r4, que es de ORO). Con Flex-Algo y TI-LFA, el respaldo se calcularía **dentro** de la topología de PLATA. Si no hubiera ninguno, PLATA se quedaría sin camino en lugar de invadir la topología de ORO, según cómo se haya diseñado.

## Parte C

**C1.** **Dos** `End.DT4` por PE, uno por VRF (`vrftable 10` y `vrftable 11`). r6 sabe a qué rebanada pertenece un paquete **por la dirección de destino**: el SID de ORO lo desencapsula en la tabla 10, el de PLATA en la 11.

**C2.** **No funciona**, y no llega a salir de r1: la VRF ORO de r1 no tiene ninguna ruta hacia `192.168.120.0/24`, porque esa ruta viene con el RT `64500:20` y ORO solo importa el `64500:10`. El aislamiento de los servicios lo hacen los RT, no la topología.

**C3.** Las dos tienen un RTT bajo (menos de un milisegundo en un laboratorio). Las dos van **por arriba**, por el camino más corto. La captura en r2 muestra los paquetes de las dos rebanadas, cada una hacia su SID de servicio en r6.

**C4.** Un `netem delay 10ms`. Hoy **no afecta a ninguna**: ninguna rebanada pasa por r3–r5.

## Parte D

**D1.** **Dos** segmentos por ruta: el `End` de un nodo intermedio y el SID de servicio. El primero de ORO es el `End` de **r4** porque basta con él: el camino más corto de r1 a r4 ya pasa por r2, y de r4 a r6 el enlace es directo. Poner también el de r2 no cambiaría el camino y añadiría 16 bytes a cada paquete.

**D2.** PLATA sube unos **20 ms** (10 ms en cada sentido del enlace r3–r5), que es justo el retardo configurado. ORO no cambia.

**D3.** Es la tabla de la sección 7 del README: PLATA desaparece de r2, ORO pasa por r2 → r4 hacia `5f00:0:4::` y PLATA por r3 → r5 hacia `5f00:0:5::`.

**D4.** Solo **PLATA**, que pasa a unos 100 ms de RTT. **Nada avisa**: IS-IS no sabe nada del retardo y el script no mide. En una red con Flex-Algo por retardo, el cambio se anunciaría (RFC 8570) y la rebanada que optimiza el retardo recalcularía su camino. Sin eso, solo una medida continua (TWAMP, módulo 17) lo detectaría.

**D5.** Con las rebanadas activas, el ping de ORO **no cambia**: PLATA va por otros enlaces. Desactivadas, las dos comparten r2 y r4. En el laboratorio el efecto es pequeño, porque los enlaces virtuales no tienen un límite de capacidad realista, pero en un enlace real saturado las colas crecerían y la latencia de ORO subiría (y podría perder paquetes). Es exactamente lo que la rebanada quiere evitar.

## Parte E

**E1.** PLATA **sigue funcionando** y su RTT baja a unos **10 ms**: la ida ya no pasa por el enlace largo, pero la vuelta sí (la estática de r6 sigue puesta).

**E2.** En r2 `eth1` aparecen los paquetes de PLATA de ida, hacia su SID de servicio en r6: van por el camino de ORO. En r3 `eth1` aparecen los de vuelta, que llegan de r5 hacia r1. La rebanada va por arriba en un sentido y por abajo en el otro, y nadie se ha quejado, porque funciona e incluso va más rápida.

**E3.** Solo midiendo: con sondas que comprueben el camino (*traceroute* SRv6, módulo 17) o la latencia de cada sentido por separado, y comparándolas con lo esperado. Con un locator propio de un algoritmo Flex-Algo, PLATA **no podría** fugarse así: la ruta hacia el SID de PLATA solo existiría en la topología de PLATA. El aislamiento lo impondría la red, no la configuración de cada PE.

**E4.** Sin las estáticas, las dos rebanadas vuelven al camino más corto, y `verificar.sh` vuelve a dar todo en verde.
