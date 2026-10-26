# E1 · Soluciones

Algunas respuestas dependen de valores que asigna FRR al arrancar (los SIDs `auto`). Donde aparece `5f00:0:6:…`, el valor exacto es el que veas en tu laboratorio.

## Parte A

**A1.** Malla completa con 10 PE: 10·9/2 = **45** sesiones. Con un RR: **10** (una por PE). Con dos RR, cada PE habla con los dos: **20** sesiones de PE a RR, más una entre los dos RR, **21** en total. Y añadir el PE número 11 solo exige configurar ese PE y los RR.

**A2.** El siguiente salto sigue siendo **r6** (`3fff:0:ff::6`) y el SID, el **`End.DT4` de r6**: un RR no cambia el siguiente salto de las rutas que refleja. r1 encapsula hacia el SID de r6, y el paquete va por el camino más corto hacia el locator de r6 (r1 → r2 → r4 → r6). Que pase por r2 es casualidad de la topología: no lo decide el RR. El tráfico hacia BLUE-3 lo demuestra (A3).

**A3.** **No** pasa por r2: va por r1 → r3 → r5 (coste 25). Si r2 se apaga unos segundos, ese tráfico **no se entera**: las rutas ya están instaladas en r1 y r5. Lo que se pierde es el plano de control: si durante ese tiempo cambiara algo (una sede nueva, una ruta que desaparece), nadie se enteraría. Y cuando las sesiones con r2 caigan del todo, los PE retirarán las rutas aprendidas: por eso, en producción, siempre hay dos RR.

**A4.** Unas **24** por arriba y **8** por abajo. El reparto real no es exacto porque cada flujo se asigna a un camino según un **hash** de sus direcciones y puertos, no por turnos: con pocos flujos, el resultado se parece a 3:1 pero puede desviarse bastante. Además, los flujos no transportan todos la misma cantidad de datos.

## Parte C

**C1.** r1 habla solo con **r2** (`3fff:0:ff::2`). Le llegan los prefijos de BLUE-2 y de BLUE-3 (y los suyos no vuelven, porque un RR no devuelve una ruta a quien se la envió). r2 tiene tres sesiones, una por PE.

**C2.** *Originator* `10.255.0.6` (r6), *Cluster list* `10.255.0.2` (r2), siguiente salto `3fff:0:ff::6`, el SID `End.DT4` de r6 (`5f00:0:6:…`) y, en las comunidades extendidas, el RT `64500:10`.

**C3.** r2 **sí** conoce las rutas VPNv4 de BLUE en su tabla BGP (es su trabajo), pero **no** las tiene en su kernel: no tiene ninguna VRF que las importe y no instala rutas VPN en la tabla global. Tampoco tiene ningún `End.DT4`. Para el plano de datos, r2 es un P más.

**C4.** **No**: el tráfico de BLUE-1 a BLUE-3 va por r3 (camino r1 → r3 → r5), y la captura en r2 no muestra nada de él. El RR está en el camino del **control**, no en el de los **datos**.

## Parte D

**D2.** Dos caminos, cada uno con su lista de dos segmentos. zebra normaliza los pesos a la escala del kernel (hasta 255): verás `weight 255` y `weight 85`, que guardan la proporción 3:1. La de BGP sigue existiendo, pero no seleccionada: la estática (distancia 1) gana a la iBGP (200).

**D3.** La proporción se parecerá a 3:1, pero rara vez será exacta (ver A4). Cuantos más flujos lances, más se acercará.

**D4.** Con **un solo** flujo, todo va por **un** camino (el que diga el hash para ese flujo), y el otro queda sin tráfico. El UCMP reparte **flujos**, no paquetes: así ningún flujo se desordena.

**D5.** Con `fib_multipath_hash_policy=0`, el hash solo usa las direcciones IP de origen y destino. Como todos los flujos van de h1 a h2, todos dan el mismo hash y van por **el mismo camino**: el reparto desaparece. Por eso el laboratorio usa la política 1 (L4: incluye los puertos).

**D6.** Al quitar las dos estáticas, vuelve a seleccionarse la ruta de BGP, con un solo segmento hacia el SID de r6.

## Parte E

**E1.** h1 llega a **h3**, pero no a **h2**. h2 tampoco llega a nadie.

**E2.** El camino de diagnóstico:

1. **Plano de datos**: en r1, `ip -6 route show 5f00:0:6::/48` sigue presente (IS-IS bien). En r6, `ip -6 route show | grep End.DT4` sigue mostrando el SID. El transporte y el SID están bien.
2. **Plano de control**: en r1, `show bgp vrf BLUE ipv4 unicast` ya no tiene `192.168.20.0/24`. En r2, `show bgp ipv4 vpn` puede seguir mostrando la ruta de r6, pero sin el RT `64500:10` en sus comunidades (o desaparecida), así que ningún PE la importa. En r6, `show bgp vrf BLUE ipv4 unicast` tampoco tiene las rutas de las otras sedes: sin RT de importación, r6 no importa nada.
3. **Causa**: en la VRF BLUE de r6 falta `rt vpn both 64500:10`.

**E3.** Vuelve a ponerlo:

```
r6(config)# router bgp 64500 vrf BLUE
r6(config-router)# address-family ipv4 unicast
r6(config-router-af)# rt vpn both 64500:10
```

Después, `./verificar.sh` debe salir en verde.
