# 06 · Soluciones

**1.** **Ingeniería de tráfico** (llevar cierto tráfico por un camino que no es el más corto: baja latencia, evitar congestión, caminos disjuntos) y **servicios VPN** (transportar las redes privadas de muchos clientes por la misma infraestructura sin que se mezclen y sin conocer sus direcciones en el núcleo).

**2.** LDP reparte una **etiqueta de transporte por cada destino**, salto a salto, para que MPLS pueda conmutar hacia cualquier prefijo del IGP. Su información está "duplicada" porque **sigue exactamente los caminos que ya calcula el IGP**: el IGP ya sabe por dónde se llega a cada destino, y LDP vuelve a distribuir esa misma topología en forma de etiquetas. Además, si LDP y el IGP se desincronizan, aparecen agujeros negros.

**3.** Para hacer ingeniería de tráfico entre *N* routers de borde con una malla completa, RSVP-TE necesita un túnel por cada par origen-destino, es decir, del orden de **N²** túneles. Y **cada router intermedio guarda estado de cada túnel que lo atraviesa**: reservas, etiquetas, temporizadores. Cuantos más routers y más túneles, más estado hay que mantener y sincronizar en todo el núcleo. No escala.

**4.** La idea central es el **encaminamiento desde el origen**: el router de entrada (headend) escribe en el paquete la lista ordenada de segmentos que forman el camino. Con eso, el **núcleo deja de guardar estado por cada camino**: solo ejecuta la instrucción que le toca y reenvía.

**5.** Elimina **LDP** y **RSVP-TE**:

- La función de LDP (repartir los segmentos de transporte) la asume el **propio IGP** (IS-IS u OSPF) con unas extensiones.
- La función de RSVP-TE (ingeniería de tráfico) la asume el **headend**, que escribe una lista de segmentos (una *SR Policy*). El estado vive solo ahí, no en el núcleo.

**6.**

| | SR-MPLS | SRv6 |
|---|---------|------|
| Un segmento es… | una etiqueta MPLS de 20 bits | una dirección IPv6 de 128 bits (el SID) |
| En el plano de datos hace falta… | MPLS en todos los routers | solo IPv6 nativo |

Los dos reparten los segmentos con el IGP y eliminan LDP/RSVP-TE; la diferencia es el plano de datos.

**7.** Son ciertas **solo para SRv6** las afirmaciones **2, 3 y 5**:

- 2 (un router de tránsito que no lo entiende reenvía igual): solo SRv6, porque el segmento es una dirección IPv6 que se reenvía por LPM. En SR-MPLS, todos los routers del camino necesitan saber conmutar MPLS.
- 3 (el servicio en la dirección): solo SRv6; en SR-MPLS el servicio sigue necesitando una etiqueta aparte.
- 5 (segmentos sumarizables como prefijos): solo SRv6; en SR-MPLS cada nodo tiene su *prefix SID* y no se agregan.
- 1 y 4 son ciertas para **los dos** (SR-MPLS también elimina LDP/RSVP-TE y también usa el IGP para repartir segmentos).

**8.**

- **RSVP-TE**: habría que señalizar un túnel explícito r1→r2→r3 y mantener su **estado en r1, r2 y r3** (reserva, etiquetas). Para distinguir a ese cliente, además, clasificar su tráfico hacia el túnel.
- **Segment Routing**: en r1 (el headend) se escribe una lista de segmentos que fuerza el paso por r2 (por ejemplo, "ve al SID de r2 y luego al de r3"). **Los routers intermedios no guardan nada**: r2 solo ejecuta su instrucción y reenvía. El estado (la política de ese cliente) vive **solo en r1**.

Esto es, de hecho, lo que hiciste a mano en el laboratorio SRv6 de la wiki: forzaste el camino r1→r2→r3 escribiendo la lista de SIDs en r1, sin tocar el estado de los demás.

**9.** Es **matizable**. En cuanto a tamaño de cabecera, MPLS es más compacto: 4 bytes por etiqueta frente a los 40 bytes de IPv6 exterior + 8 de SRH + 16 por SID del SRv6 clásico. Así que, byte a byte, SRv6 **no** es más pequeño. Donde SRv6 gana es en **simplicidad operativa**: un solo plano de datos de extremo a extremo y la mitad de protocolos. Además, con **uSID** (módulo 10) la sobrecarga por SID casi desaparece y SRv6 se pone a la par de una pila de etiquetas MPLS. La afirmación correcta sería: "SRv6 simplifica la red, y con uSID su sobrecarga deja de ser un problema", no que sus cabeceras sean más pequeñas.

**10.** Porque, como viste en el módulo 02, SRv6 usa una **cabecera de extensión** (la SRH, un Routing Header), y muchos equipos y cortafuegos en Internet **descartan** los paquetes con cabeceras de extensión. Dentro del dominio de un operador, este controla todos los equipos y puede garantizar que la SRH se procesa; a través de Internet abierto, no. Por eso SRv6 es una tecnología **intradominio**, y en el borde se filtra para que no entre ni salga (módulo 17).
