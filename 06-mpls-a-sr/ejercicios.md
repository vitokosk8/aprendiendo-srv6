# 06 · Ejercicios de repaso

Este módulo es conceptual, así que los ejercicios son de razonamiento, no de laboratorio. Hazlos sin mirar; las soluciones están en [soluciones.md](soluciones.md).

**1.** Una red de operador ya tiene IS-IS funcionando y mueve el tráfico por el camino más corto. Nombra **dos** cosas que todavía no puede hacer y para las que, históricamente, se usó MPLS.

**2.** ¿Qué trabajo hace LDP en una red MPLS clásica? ¿Por qué se dice que su información está "duplicada" respecto al IGP?

**3.** Explica el problema de escala de RSVP-TE. ¿Por qué se habla de "N² túneles" y dónde se guarda el estado?

**4.** En una frase: ¿cuál es la idea central de Segment Routing, y qué consigue que el núcleo **deje** de hacer?

**5.** Segment Routing elimina dos protocolos de la red MPLS clásica. ¿Cuáles, y quién asume ahora cada una de sus funciones?

**6.** ¿En qué se diferencian SR-MPLS y SRv6? Para cada uno, di qué es un "segmento" y qué hace falta tener en el plano de datos.

**7.** Marca cuáles de estas afirmaciones son ciertas **solo para SRv6** (no para SR-MPLS):

1. Elimina LDP y RSVP-TE.
2. Un router de tránsito que no lo entiende puede reenviar el paquete igualmente.
3. El servicio de VPN puede ir codificado en la propia dirección de destino.
4. El IGP reparte los segmentos.
5. Los identificadores de segmento se pueden sumarizar como prefijos.

**8.** En el módulo 05 viste que al loopback de r3 se llegaba por el camino más corto que calcula SPF. Si quisieras que *un cliente concreto* fuese de r1 a r3 **por r2** (no por el enlace directo), ¿cómo lo haría RSVP-TE y cómo lo haría Segment Routing? ¿Dónde queda el estado en cada caso?

**9.** Un compañero dice: "SRv6 es más eficiente que MPLS porque sus cabeceras son más pequeñas". ¿Es correcto? Matiza la afirmación.

**10.** ¿Por qué SRv6 se despliega dentro del dominio de un operador y no a través de Internet abierto? Relaciónalo con lo que aprendiste en el módulo 02.
