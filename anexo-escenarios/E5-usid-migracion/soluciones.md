# E5 · Soluciones

Vuelve a la [práctica](practica.md) o al [escenario](README.md).

## Parte A

**A1.** Con F3216 quedan 128 − 32 = 96 bits para uSID de 16: caben **6**. El camino r1 → r2 → r3 → r5 → r6 con el uDT46 de r6 necesita **5** (`0002`, `0003`, `0005`, `0006` y la función `e000`):

```
5f00:0:2:3:5:6:e000::
```

Cabe en una sola dirección: **no hace falta SRH**. r1 no aparece porque es quien encapsula. Y el uN de r6 hace falta: es lo que lleva el paquete hasta r6 antes de que r6 lea su función.

**A2.** Con SIDs clásicos son **4** SIDs (`End` de r2, r3 y r5, y el `End.DT46` de r6): 40 (IPv6 exterior) + 8 (cabecera de la SRH) + 4·16 = **112 bytes**. Con uSID, solo la cabecera exterior: **40 bytes**. Con un paquete de 1.500 bytes que no quieras fragmentar, son 72 bytes más de carga útil.

**A3.** **Sí funciona, aunque por casualidad.** Cuando r3 desplaza su uSID, `5f00:0:3:5::` se convierte en `5f00:0:5::`, que es exactamente el `End` clásico de r5. r5 lo procesa como siempre: pasa al siguiente segmento de la SRH, el SID de r6. Funciona porque r5 es el **último** uSID del contenedor y su `End` clásico es la dirección del locator con todo a cero. Si r5 estuviera en medio o al principio del contenedor, fallaría: es lo que provoca la parte D. No conviene confiar en esta coincidencia: un SID clásico no tiene por qué tener función cero.

**A4.** Si esa red enruta **IPv6**, **no necesitas nada especial**: los SIDs son direcciones IPv6, y basta con que esa red conozca las rutas hacia los locators de las dos islas (redistribuyéndolas o con un IGP común) y que no filtre los paquetes con SRH (cabecera de enrutamiento tipo 4). Si es **solo IPv4**, unes las dos islas con un **túnel GRE** de IPv6 sobre IPv4 entre los routers frontera y levantas IS-IS sobre él. Cuenta con los 24 bytes del túnel en la MTU.

## Parte B

**B1.** IS-IS asignó el **uN** del nodo y un **uA** por cada adyacencia. BGP asignó el **uDT46** de la VRF BLUE. Son los equivalentes comprimidos de `End`, `End.X` y `End.DT46`.

**B2.** El uN es un **`/48`**: cubre todo el locator, porque tiene que procesar **cualquier** contenedor en el que `0001` sea el uSID activo, lleve lo que lleve detrás. Un `End` clásico es un `/128` porque solo hay una dirección que lo active. El uDT46 tiene un prefijo más largo (el locator más su función) y **no tiene flavor**: el kernel lo instala como un `End.DT46` normal, porque, al ser el último uSID, no hay nada que desplazar.

**B3.** **Un** solo SID, el uDT46 de r6 (`5f00:0:6:XXXX::`), en modo `encap.red`, y **sin SRH**: en la captura de r2, después de la cabecera IPv6 viene directamente el paquete IPv4 (*Next Header* 4). Es igual que con SIDs clásicos: con un solo SID, uSID no ahorra nada.

**B4.** En **r3** el destino es el contenedor **`5f00:0:5:6:XXXX::`**: r3 no lo procesa, lo reenvía por la ruta del locator de r5. En **r6** el destino es **`5f00:0:6:XXXX::`**: lo cambió **r5**, que, con su uN, desplazó el resto del contenedor 16 bits a la izquierda. **En ningún momento lleva SRH.** Con SIDs clásicos, el mismo camino llevaba una SRH de dos segmentos (como en E1).

**B5.** Al quitar la estática, se vuelve a seleccionar la ruta de BGP, con un solo SID.

## Parte C

**C1.** r1 tiene un **uDT46** y r6 un **`End.DT46` clásico**. r1 encapsula hacia el `End.DT46` de r6, y r6 hacia el uDT46 de r1. **Ninguno necesita saber de qué tipo es el SID del otro**: BGP le da una dirección y el PE encapsula hacia ella. Solo el dueño del SID tiene que saber ejecutarlo.

**C2.** Los dos usan la **ruta del locator de r6** (`5f00:0:6::/48`) que aprendieron por IS-IS, como cualquier otra ruta IPv6. Que r2 sea uSID y r4 clásico no cambia nada: el tránsito no procesa SIDs ajenos.

**C3.** Tres segmentos, en modo **`encap`** (con SRH): `staticd` usa `H.Encaps` si no le dices otra cosa. En r5, el destino ya es **`5f00:0:5::`** (r3 consumió su segmento) y *Segments Left* vale **1**: queda un segmento por visitar, el SID de r6. r3 procesó su uN como un `End` clásico porque detrás de su uSID no había nada que desplazar.

**C4.** Porque **r5 no entiende uN**: no sabe desplazar un contenedor. Un contenedor solo puede llevar uSID de routers que soportan uN. Para r5, la única forma de aparecer en la lista es con un SID clásico entero.

## Parte D

**D1.** **No llega.** Y la ruta de r1 parece perfecta: dos segmentos, `5f00:0:5:3::` y el SID de r6, por r3. Nada en r1 avisa del problema.

**D2.** El paquete **llega a r5**: lo ves pasar por r3 (`eth3`) y entrar en r5 (`eth1`) con destino `5f00:0:5:3::`. Pero ninguna de las rutas `seg6local` de r5 coincide con esa dirección: su `End` es `5f00:0:5::/128` y sus `End.X` son otras direcciones `/128`. r5 no tiene ningún SID que le diga qué hacer, así que nunca llega a mirar la SRH, y el paquete muere en r5. `ip -6 route get` te muestra qué ruta usa el kernel para ese destino, y no es ningún `seg6local`. Es el error típico de una migración: un controlador o un operador que mete en un contenedor un router que aún no está migrado.

**D3.** Al quitar la estática, la ruta vuelve a la de BGP y `verificar.sh` vuelve a dar todo en verde.
