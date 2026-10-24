# EN · Título del escenario

> **El caso en una frase**: …
>
> **Requisitos previos**: módulos …, … y … · Probado con containerlab …, FRR …, netshoot … · Estado: 🧪

## El escenario

<!-- topologia:inicio -->
<!-- topologia:fin -->

Qué se añade a la [topología base](../topologia-base/README.md) (equipos nuevos y en qué enganche) y qué se configura en los PE. Enlace a la [práctica](practica.md).

## 1. El caso de uso

Quién es el cliente, qué tiene y qué problema quiere resolver. Contado como lo contaría el cliente, sin hablar todavía de SRv6.

## 2. Criterios de éxito

Lo que pide el cliente, escrito como comprobaciones concretas. El `lab/verificar.sh` comprueba exactamente esta lista.

- [ ] …
- [ ] …

## 3. La solución con SRv6

El diseño: qué hace cada equipo, qué SIDs se usan y cómo viaja un paquete de punta a punta.

## 4. Decisiones de diseño

| Decisión | Por qué | Alternativa descartada |
|---|---|---|
| … | … | … |

## 5. Primero, por el camino más corto (SRv6 BE)

La solución sobre el camino que elige IS-IS. Configuración de los PE, comentada.

## 6. Después, con ingeniería de tráfico

El mismo servicio, forzando otro camino de la topología base. Qué cambia y qué no.

## 7. Lo que verás en el cable

La captura de referencia: cabecera exterior, SIDs y paquete interior.

## 8. Rómpelo y arréglalo

Un fallo provocado, los síntomas que verás y cómo diagnosticarlo con lo aprendido en el módulo 17.

## 9. En producción

Qué cambiaría en una red real, y qué parte no cubre FRR hoy.

## 10. Resumen

- …

## Para saber más

- …
