# E3 · Soluciones

## Parte A

**A1.** **No**: una L3VPN solo transporta IP, porque el PE de salida busca la IP de destino en una tabla de rutas. Le ofrecería un **EVPN VPWS**: el PE de salida usa un **`End.DX2`**, que saca la trama Ethernet por el circuito de la sede sin mirar lo que lleva dentro, sea IP o no.

**A2.** La trama a una MAC conocida va hacia el **`End.DT2U`** del PE donde está esa MAC, que le llegó con la **ruta tipo 2** que anunció esa MAC. La de difusión se **replica** hacia los **`End.DT2M`** de los otros cuatro PE de la EVI, aprendidos con sus **rutas tipo 3**: una copia por PE.

**A3.** En el cable, **ninguna**: los dos usan un SID `End.DT4` (o `End.DT46`) del PE de salida, y el paquete IPv4 va igual dentro de IPv6 y SRH. En BGP, la L3VPN usa la familia **VPNv4** y EVPN usa la familia **L2VPN EVPN** con rutas **tipo 5**.

**A4.** El `End.DX2` siempre entrega por **una** interfaz: no hay nada que elegir. El `End.DT2M` **inunda** por todas las interfaces de la EVI, y con *multihoming* tiene que saber de qué segmento Ethernet viene la trama para **no devolverla** a la sede de la que salió. El PE de entrada se lo dice con el argumento del SID.

## Parte C

**C1.** Por **`eth4`**, la interfaz hacia la sede 2 (sw2). Esa interfaz **no tiene ninguna dirección IPv4**, y solo la IPv6 *link-local* que Linux pone automáticamente: es un circuito de capa 2, no una interfaz de router.

**C2.** El *Next Header* de la SRH es **143** (Ethernet). Dentro viaja la **trama Ethernet completa**: 6 bytes de MAC de destino (`ff:ff:ff:ff:ff:ff`), 6 de MAC de origen (la de h11), el tipo `0x0806` (ARP) y el mensaje ARP. scapy la muestra como `Raw` porque no sabe interpretar una trama Ethernet después de una SRH. La sobrecarga es de **64 bytes**: 40 de IPv6 y 24 de SRH (8 fijos y un segmento de 16).

**C3.** La trama llega a h12 con la **MAC de origen de h11**, como si h11 estuviera en su misma LAN. h12 la procesa como una petición ARP normal: contesta y **apunta en su tabla** que `192.168.100.11` está en la MAC de h11 (lo ves con `ip neigh`).

**C4.** **No**: r2 solo ve un paquete IPv6 hacia `5f00:0:6:d2::`, y lo reenvía con su ruta IS-IS hacia `5f00:0:6::/48`. Con `-v`, tcpdump muestra la SRH y el *Next Header* 143, pero r2 no mira lo que hay dentro.

**C5.** **No llega**. La respuesta de h12 sale por su `eth1`, cruza sw2 y llega a r6 por `eth4`, y ahí se queda: r6 no tiene configurada la otra mitad del VPWS, el **`H.Encaps.L2`** que encapsularía todo lo que entra por `eth4` hacia el `End.DX2` de r1. En un router con EVPN, esa mitad la configura el propio servicio VPWS. Aquí, para mandar tramas de la sede 2 a la sede 1, tienes que usar el script desde r6 (`--net container:clab-esc-e3-r6` y el SID `5f00:0:1:d2::`).

**C6.** **No** tiene ninguna ruta hacia `192.168.100.0/24`, ni la necesita: en un VPWS, el PE no enruta, solo transporta tramas de un extremo al otro. En la L3VPN del módulo 12, en cambio, el PE tenía en su VRF las rutas de todas las sedes del cliente, porque el `End.DT4` del PE de salida busca la IP de destino en esa tabla.

## Parte D

**D1.** h12 **ya no ve nada**. r6 sigue recibiendo y desencapsulando las tramas, pero las saca por **`eth3`**, hacia h2: la captura en r6 `eth3` muestra la petición ARP de h11 entrando en otra sede. Es el error típico de un VPWS (y uno grave, porque mezcla el tráfico de dos clientes): el circuito está mal asociado al servicio. En un router con EVPN se ve en la configuración del VPWS, comparando la interfaz o VLAN de cada extremo.

**D2.** En r6:

```
$ docker exec clab-esc-e3-r6 ip -6 route replace 5f00:0:6:d2::/128 encap seg6local action End.DX2 oif eth4 dev eth4
```

Después, `./verificar.sh` debe salir en verde.
