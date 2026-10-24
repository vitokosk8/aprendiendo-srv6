# 14 · Soluciones

> Las salidas son orientativas; los valores de función de los SIDs que asigna FRR (End/End.X) variarán entre despliegues. El waypoint `5f00:0:3:e000::` y los `End.DX4` sí son fijos (puestos a mano).

## Parte A

**A1.** Porque el IGP solo optimiza el **coste** (camino más corto), y la realidad tiene otros criterios. Dos motivos: (1) **congestión** — el camino corto puede estar saturado y quieres desviar por otro; (2) **latencia/SLA** — un cliente puede necesitar la ruta de menor retardo, que no es la de menos saltos (o evitar un enlace, separar servicios, esquivar un nodo en mantenimiento).

**A2.** `segs = [5f00:0:3:e000::, 5f00:0:4:dc04::]`:
- **`5f00:0:3:e000::`** (End de r3): el paquete va primero **a r3**; r3 ejecuta `End` y pasa al siguiente SID. Esto fuerza el paso por r3.
- **`5f00:0:4:dc04::`** (End.DX4 de r4): r4 desencapsula y entrega el IPv4 a h2.

**A3.** Con SRv6, el camino va **codificado en el paquete** (la lista de segmentos), así que los routers del núcleo (r2/r3/r4) **no guardan estado por-flujo**: solo ejecutan el SID que les toca. Con RSVP-TE de MPLS, cada router del túnel mantiene **estado** del LSP (reservas, etiquetas por túnel). SRv6 hace TE **sin estado** en el núcleo → escala mucho mejor.

**A4.**
- **Color**: número que representa una **intención** (p. ej. "baja latencia", "evita r2").
- **Endpoint**: el **destino** de la política (el nodo al que lleva).
- **Candidate path**: un camino candidato de la política (explícito o dinámico), con una **preferencia**; gana el de mayor preferencia operativo.
- **Binding SID (BSID)**: un SID que **representa a toda la política**; mandar tráfico al BSID equivale a "mételo en esta política".

**A5.** FRR **sí** hace el **transporte** (locators y SIDs End/End.X por IS-IS) y SR Policy para **SR-MPLS**. FRR **no** hace SR Policy para **SRv6** (su `pathd` no admite segmentos SRv6). Para TE SRv6 automatizada (color/ODN/PCE) usarías una plataforma que lo soporte: **Cisco IOS-XR, Juniper, Nokia SR OS**, o un controlador SR.

## Parte B

### B1
1. El camino más corto a r4 sale por **r2 (`eth2`)**, con coste **20** (dos enlaces de métrica 10).
2. El camino por r3 cuesta **30** porque el enlace **r1–r3 tiene métrica 20** (20 + 10). Por eso el IGP prefiere r2.

### B2
1. El tráfico pasa por **r3** (el camino **largo**), **no** por el más corto del IGP. En la captura de r2 no se ve nada; en la de r3 sí.
2. `ip route show 10.0.2.0/24` muestra `encap seg6 ... segs 2 [5f00:0:3:e000:: 5f00:0:4:dc04::]`. El primer SID es el **waypoint de r3**: eso es lo que fuerza el desvío.

### B3
1. Ahora el tráfico va por **r2** (el camino corto): la captura de r2 lo ve, la de r3 no.
2. Con un solo SID (`5f00:0:4:dc04::`, el de r4), el destino exterior es directamente r4, así que **el IGP** decide el camino hasta r4 → elige el corto (por r2). Tú no fuerzas nada intermedio.
3. (Se restaura el waypoint por r3 con el `ip route replace ... segs 5f00:0:3:e000::,5f00:0:4:dc04::`.)

### B4
1. En r3 verás el `End` del locator (`5f00:0:3::/48 ... action End ... dev sr0`) y uno o más `End.X` hacia sus vecinos (r1 y r4), con sus valores de función asignados por FRR.
2. (Opcional) Usando el `End.X` de r3 **hacia r4** como primer segmento, el camino sigue siendo r1→r3→r4 y el ping funciona.
3. Con el **End del nodo** r3, el tramo r3→r4 lo decide el **IGP** (el camino más corto desde r3, que es el enlace directo r3–r4). Con un **End.X** de r3 **hacia r4**, fuerzas explícitamente ese enlace, sin depender del IGP. El End.X da control salto a salto (útil si r3 tuviera varios caminos a r4); el End del nodo deja el último tramo al IGP.

### B5
1. Pseudo-config (estilo IOS-XR, no FRR):
   ```
   segment-routing traffic-eng
    policy EVITA-CORTO
     color 200 end-point ipv6 3fff:0:ff::4
     candidate-paths
      preference 100
       explicit segment-list VIA-R3
    segment-list VIA-R3
     index 10 srv6 sid 5f00:0:3:e000::
     index 20 srv6 sid 5f00:0:4:dc04::
   ```
2. Por **color + BGP**: la ruta de la red de h2 llegaría con una *Color Extended Community* (color 200) y next-hop = r4; al coincidir color+endpoint con la política, el tráfico entra en ella automáticamente (*automated steering*).
3. El **binding SID** representaría toda la política con un único SID: otros nodos (o políticas) podrían dirigir tráfico "a la política" mandándolo al BSID, sin conocer la lista interna, y permitiría encadenar políticas.

### Reto
1. En la ida (r1→r4), `segs = [5f00:0:3:e000::, 5f00:0:4:dc04::]` pasa por r3 y nunca por r2. En la vuelta (r4→r1), `segs = [5f00:0:3:e000::, 5f00:0:1:dc04::]` (waypoint r3 + End.DX4 de r1). Las dos evitan r2.
2. Es justo lo que hace el laboratorio por defecto. Con `docker stop clab-m14-r2`, el ping **sigue funcionando**, porque el tráfico ya iba por r3.
3. No es resiliencia automática porque **tú** fijaste el camino por r3; si cayera **r3**, nadie recalcula un respaldo y el tráfico se perdería (la lista apunta a un r3 que ya no está). La protección automática ante fallos —precalcular un respaldo con SIDs— es **TI-LFA**, el módulo 15.
