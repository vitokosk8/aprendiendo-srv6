# 21 · Práctica: BIER

Antes de empezar, lee la [teoría del módulo](README.md). Los contenedores se llaman `clab-m21-…`. Los comandos con `./` se ejecutan desde la carpeta `lab/`.

## Topología

<!-- topologia:inicio -->
```mermaid
graph LR
    h1("🖥️ <b>h1</b><br/>fuente multicast · grupo 233.252.0.1<br/>eth1: 10.0.1.10/24")
    r1("<b>r1</b><br/>BFIR · BFR-id 1<br/>lo: 3fff:0:ff::1/128 (BFR-prefix)<br/>eth1: 10.0.1.1/24<br/>eth2: 3fff:0:12::1/64<br/>locator 5f00:0:1::/48<br/>SID End/End.X (IS-IS)")
    r2("<b>r2</b><br/>BFR de tránsito (sin BFR-id)<br/>lo: 3fff:0:ff::2/128<br/>eth1: 3fff:0:12::2/64<br/>eth2: 3fff:0:23::2/64<br/>eth3: 3fff:0:24::2/64<br/>eth4: 3fff:0:25::2/64<br/>locator 5f00:0:2::/48<br/>SID End/End.X (IS-IS)")
    r3("<b>r3</b><br/>BFER · BFR-id 3<br/>lo: 3fff:0:ff::3/128 (BFR-prefix)<br/>eth1: 3fff:0:23::3/64<br/>eth2: 10.0.3.1/24<br/>locator 5f00:0:3::/48<br/>SID End/End.X (IS-IS)")
    r4("<b>r4</b><br/>BFER · BFR-id 4<br/>lo: 3fff:0:ff::4/128 (BFR-prefix)<br/>eth1: 3fff:0:24::4/64<br/>eth2: 10.0.4.1/24<br/>locator 5f00:0:4::/48<br/>SID End/End.X (IS-IS)")
    r5("<b>r5</b><br/>BFER y BFR · BFR-id 5<br/>lo: 3fff:0:ff::5/128 (BFR-prefix)<br/>eth1: 3fff:0:25::5/64<br/>eth2: 10.0.5.1/24<br/>eth3: 3fff:0:56::5/64<br/>locator 5f00:0:5::/48<br/>SID End/End.X (IS-IS)")
    h3("🖥️ <b>h3</b><br/>receptor<br/>eth1: 10.0.3.30/24")
    h4("🖥️ <b>h4</b><br/>receptor<br/>eth1: 10.0.4.40/24")
    r6("<b>r6</b><br/>BFER · BFR-id 6<br/>lo: 3fff:0:ff::6/128 (BFR-prefix)<br/>eth1: 3fff:0:56::6/64<br/>eth2: 10.0.6.1/24<br/>locator 5f00:0:6::/48<br/>SID End/End.X (IS-IS)")
    h5("🖥️ <b>h5</b><br/>receptor<br/>eth1: 10.0.5.50/24")
    h6("🖥️ <b>h6</b><br/>receptor<br/>eth1: 10.0.6.60/24")

    r1 -- "eth2 ⟷ eth1<br/>3fff:0:12::/64" --- r2
    r2 -- "eth2 ⟷ eth1<br/>3fff:0:23::/64" --- r3
    r2 -- "eth3 ⟷ eth1<br/>3fff:0:24::/64" --- r4
    r2 -- "eth4 ⟷ eth1<br/>3fff:0:25::/64" --- r5
    r5 -- "eth3 ⟷ eth1<br/>3fff:0:56::/64" --- r6
    h1 -- "eth1 ⟷ eth1<br/>10.0.1.0/24" --- r1
    r3 -- "eth2 ⟷ eth1<br/>10.0.3.0/24" --- h3
    r4 -- "eth2 ⟷ eth1<br/>10.0.4.0/24" --- h4
    r5 -- "eth2 ⟷ eth1<br/>10.0.5.0/24" --- h5
    r6 -- "eth2 ⟷ eth1<br/>10.0.6.0/24" --- h6

    classDef router fill:#ddf4ff,stroke:#0969da,stroke-width:2px,color:#1f2328
    classDef host fill:#dafbe1,stroke:#1a7f37,stroke-width:2px,color:#1f2328
    classDef switch fill:#f6f8fa,stroke:#57606a,stroke-width:2px,color:#1f2328
    class r1,r2,r3,r4,r5,r6 router
    class h1,h3,h4,h5,h6 host
```
<!-- topologia:fin -->

## Parte A · Ejercicios en papel

**A1.** Escribe en binario y en hexadecimal el BitString de un paquete para los BFER 3 y 6. ¿Y para los BFER 1, 2 y 64, con un BitString de 64 bits?

**A2.** Escribe la BIFT de r5 (vecinos, interfaces y F-BM) y la de r1. Ten en cuenta que en el dominio también está r1, con BFR-id 1.

**A3.** A r2 le llega un paquete con el BitString {4, 6}. Aplica el algoritmo de la sección 4: ¿cuántas copias envía, por dónde y con qué BitString cada una?

**A4.** Una red tiene 1000 PE de salida y usa un BitString de 256 bits. ¿Cuántos conjuntos (SI) hacen falta? Si un grupo tiene un receptor en cada uno de los 1000 PE, ¿cuántos paquetes envía el BFIR por cada paquete del grupo? ¿Y si los receptores están todos en los PE 1 a 200?

**A5.** En el módulo 20, si un receptor de r4 se iba, ¿qué había que cambiar? ¿Y aquí?

## Parte B · Levantar y verificar

```
$ cd 21-bier/lab
$ sudo containerlab deploy -t lab.clab.yml
$ ./verificar.sh
```

## Parte C · La BIFT

**C1.** Mira la BIFT de r1, r2 y r5 (`cat /tmp/bift.txt`) y compárala con lo que escribiste en A2.

**C2.** Comprueba de dónde sale la entrada {5, 6} de r2:

```
$ docker exec clab-m21-r2 ip -6 route get 3fff:0:ff::5
$ docker exec clab-m21-r2 ip -6 route get 3fff:0:ff::6
```

¿Qué tienen en común las dos rutas?

**C3.** ¿Por qué no hay ninguna entrada para r2 en ninguna BIFT? ¿Qué pasaría si quisieras poner un receptor detrás de r2?

## Parte D · El BitString en el cable

**D1.** Abre el registro de r2 y de r5 y envía un datagrama:

```
$ docker exec clab-m21-r2 tail -f /tmp/bier.log
$ docker exec clab-m21-h1 bash -c "echo hola | socat -u - UDP4-DATAGRAM:233.252.0.1:5000,ip-multicast-ttl=8"
```

Compara lo que hace cada uno con tu respuesta a A3 y con la sección 4 de la teoría.

**D2.** Captura en r5 (`eth1`) con `-x` mientras envías otro datagrama. Localiza en el volcado hexadecimal:
- el Next Header de la cabecera IPv6 (byte 6);
- el *Hop Limit* (byte 7) y las direcciones de origen y destino: ¿qué tipo de direcciones son?;
- el TTL BIER (byte 43), el campo Proto y el BFIR-id;
- el BitString (bytes 52 a 59).

**D3.** Haz lo mismo en r6 (`eth1`). ¿Qué ha cambiado en el BitString? ¿Y en el TTL BIER?

## Parte E · Cambiar los receptores

**E1.** El receptor de r4 se va. En `lab/bier/entrada-r1.txt`, quita `r4` de la línea del grupo. Envía un datagrama. ¿Qué BitString pone r1? Captura en r2 `eth1` para comprobarlo.

**E2.** Mira la BIFT de r2 antes y después del cambio. ¿Ha cambiado algo? ¿Y en el módulo 20, cuando quitaste una rama?

**E3.** Ahora quita también `r5`, pero deja `r6`. ¿Qué hace r5 con el paquete? ¿Lo entrega a h5? Míralo en su registro. Deja el fichero como estaba.

## Parte F · Rómpelo y arréglalo

**F1.** Para el router BIER de r5:

```
$ docker exec clab-m21-r5 pkill -f bier.py
```

Envía un datagrama. ¿Quién lo recibe y quién no? ¿Ha cambiado algo en las BIFT de r1 y r2? ¿Por qué el IGP no lo arregla?

**F2.** ¿Qué pasaría si, en vez de parar el script, se cayera el enlace r2–r5? (Pista: piensa en qué ve IS-IS y en cuándo se recalcula la BIFT de r2.)

**F3.** Vuelve a arrancar el router BIER de r5 y comprueba con `./verificar.sh` que todo vuelve a estar en verde:

```
$ docker exec -d clab-m21-r5 bash -c 'python3 -u /bier/bier.py r5 >> /tmp/bier.log 2>&1'
```

## Al terminar

```
$ sudo containerlab destroy -t lab.clab.yml --cleanup
```

Compara tus respuestas con las [soluciones](soluciones.md).
