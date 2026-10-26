# 00 · Preparación del entorno

Todos los laboratorios del curso se ejecutan con contenedores. Necesitas tres cosas:

| Pieza | Para qué sirve |
|-------|----------------|
| **Docker** | Ejecuta los contenedores. En macOS se recomienda [OrbStack](https://orbstack.dev); en Linux, Docker Engine |
| **Containerlab** | Crea la topología: arranca los contenedores y los cablea entre sí con enlaces virtuales |
| **Imágenes** | `quay.io/frrouting/frr` para los routers y `nicolaka/netshoot` para los hosts y las capturas |

## macOS con OrbStack

Containerlab necesita Linux. Con OrbStack se crea una máquina Linux ligera y se trabaja desde ella:

```bash
$ orb create ubuntu clab        # crea la máquina "clab"
$ orb -m clab                   # entra en ella
$ bash -c "$(curl -sL https://get.containerlab.dev)"
$ containerlab version
```

Desde la máquina de OrbStack ves tu carpeta personal del Mac en `/Users/<tu-usuario>`, así que puedes clonar el repositorio en el Mac y lanzar los laboratorios desde la máquina Linux.

## Linux

Instala [Docker Engine](https://docs.docker.com/engine/install/) y después Containerlab:

```bash
$ bash -c "$(curl -sL https://get.containerlab.dev)"
```

## Descarga de imágenes

```bash
$ docker pull quay.io/frrouting/frr:10.7.1
$ docker pull nicolaka/netshoot:v0.13
```

## Comprobación del kernel

SRv6 se implementa en el kernel de Linux. Los contenedores usan el kernel del anfitrión, así que conviene comprobar que lo soporta:

```bash
$ uname -r                              # cualquier kernel ≥ 5.x vale para empezar
$ docker run --rm --privileged nicolaka/netshoot:v0.13 \
    sysctl net.ipv6.conf.all.seg6_enabled
net.ipv6.conf.all.seg6_enabled = 0      # si la clave existe, el kernel soporta SRv6
```

Si aparece `No such file or directory`, el kernel no tiene SRv6. Los módulos 01 a 05 funcionarán igualmente, pero a partir del 07 necesitarás otro kernel.

## Ciclo de vida de un laboratorio

```bash
$ cd 01-direccion-ipv6/lab
$ sudo containerlab deploy -t lab.clab.yml        # levantar
$ sudo containerlab inspect -t lab.clab.yml       # ver estado
$ docker exec -it clab-m01-h1 bash                # entrar en un nodo
$ sudo containerlab destroy -t lab.clab.yml --cleanup   # destruir
```

Los contenedores se llaman `clab-<nombre-del-lab>-<nodo>`, por ejemplo `clab-m01-h1`.

## Dibujar la topología

Cada laboratorio incluye su esquema de conexionado en dos formatos:

- **Mermaid**, en la portada del módulo (`README.md`) y en el enunciado de la práctica (`practica.md`): GitHub lo dibuja directamente.
- **draw.io**, en `lab/topologia.drawio`: se abre en [app.diagrams.net](https://app.diagrams.net) o en VS Code (extensión *Draw.io Integration*) para recolocar nodos, retocarlo o exportarlo a PNG/PDF.

Los dos se generan con [`herramientas/topologia.py`](../herramientas/topologia.py) a partir de las etiquetas (`labels`) de cada nodo en `lab.clab.yml`, que es la única fuente de verdad:

```yaml
r2:
  labels:
    graph-level: 2                 # columna, de izquierda a derecha
    graph-row: 1                   # fila dentro de la columna (opcional)
    graph-icon: router             # router | host
    ip.lo: "3fff:0:ff::2/128"      # dirección de cada interfaz: ip.<interfaz>
    ip.eth1: "3fff:0:12::2/64"
    srv6.locator: "5f00:0:2::/48"
    srv6.sids: "5f00:0:2:e000:: End; 5f00:0:2:e001:: End.DT6"
```

Para regenerarlos después de cambiar un laboratorio (necesita PyYAML):

```bash
$ sudo apt install -y python3-yaml          # en la máquina Linux de OrbStack, una sola vez
$ python3 herramientas/topologia.py 01-direccion-ipv6/lab/lab.clab.yml
✔ 01-direccion-ipv6/lab/topologia.drawio
✔ 01-direccion-ipv6/README.md (diagrama actualizado)
✔ 01-direccion-ipv6/practica.md (diagrama actualizado)
```

El script sustituye el diagrama de `README.md` y de `practica.md` que está entre los marcadores `<!-- topologia:inicio -->` y `<!-- topologia:fin -->`.

Containerlab también sabe dibujar topologías por sí mismo (`containerlab graph --drawio` o `--mermaid`), pero no muestra direcciones ni SIDs; por eso el curso usa su propio generador.

## Capturar tráfico

Los hosts usan la imagen `netshoot`, que ya incluye `tcpdump` y `tshark`. Para capturar en un router FRR, que no trae `tcpdump`, se "engancha" un contenedor netshoot a su espacio de red:

```bash
$ docker run --rm -it --net container:clab-m01-r1 nicolaka/netshoot:v0.13 \
    tcpdump -ni eth1 -vv
```

## Una trampa a tener en cuenta

Containerlab conecta cada nodo a una red de gestión a través de `eth0`, y esa red tiene una **ruta por defecto IPv6**. Si en el laboratorio falta una ruta, el tráfico puede escaparse por `eth0` y parecer que todo funciona. Por eso todos los laboratorios del curso borran esa ruta al arrancar.
