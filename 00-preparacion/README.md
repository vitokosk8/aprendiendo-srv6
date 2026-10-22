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
$ docker pull quay.io/frrouting/frr:10.2.1
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

## Capturar tráfico

Los hosts usan la imagen `netshoot`, que ya incluye `tcpdump` y `tshark`. Para capturar en un router FRR, que no trae `tcpdump`, se "engancha" un contenedor netshoot a su espacio de red:

```bash
$ docker run --rm -it --net container:clab-m01-r1 nicolaka/netshoot:v0.13 \
    tcpdump -ni eth1 -vv
```

## Una trampa a tener en cuenta

Containerlab conecta cada nodo a una red de gestión a través de `eth0`, y esa red tiene una **ruta por defecto IPv6**. Si en el laboratorio falta una ruta, el tráfico puede escaparse por `eth0` y parecer que todo funciona. Por eso todos los laboratorios del curso borran esa ruta al arrancar.
