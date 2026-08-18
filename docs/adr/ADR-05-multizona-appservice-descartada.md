# ADR-05: Multi-zona en App Service — diseño objetivo Premium v2/v3, no implementado en esta suscripción

**Estado:** Aceptada — 2026-08-15, reencuadrada 2026-08-16 (diseño objetivo primero, restricción de suscripción como nota secundaria)
**Sección U4 afectada:** 3. Escalabilidad y Alta Disponibilidad
**Relacionada:** ADR-04 (misma sección, decisión complementaria)

## Diseño objetivo (arquitectura de referencia, sin restricción de suscripción)

Para `api-novapay-{env}`, el diseño de alta disponibilidad correcto es un **App Service Plan Premium v3, zone-redundant**, con un mínimo de 2 instancias siempre activas repartidas automáticamente entre zonas de disponibilidad de la región — el mínimo que Azure exige para sostener el SLA de 99.99% en este modelo (reducido desde 3 instancias en versiones anteriores de la plataforma). A diferencia del Function App (donde la Sección 3.2.1 acepta activación puntual para no romper el escalado a cero), el App Service transaccional **no** tiene ese mismo argumento de elasticidad: ya corre con instancias siempre activas por diseño desde la Entrega 1 (1-2 en dev, 3-24 en prod, autoescalado por CPU), así que zone-redundancy ahí no compite con ningún modelo de pago-por-uso ni rompe ningún escalado a cero existente. Eso **no** significa que sea gratis: el salto de tier Standard S1 → Premium v3 es en sí mismo un incremento de costo real (independiente de zone-redundancy), y habilitar zone-redundancy además sube el piso mínimo de instancias de 1 a 2 en dev (el mínimo que exige la plataforma), un costo adicional concreto en ese ambiente. El argumento correcto no es "sin costo", es **"sin el trade-off de elasticidad que sí tiene el Function App"** — la resiliencia zonal aquí es una decisión de costo vs. disponibilidad ordinaria, no una que además sacrifique la propiedad de escalar a cero. Este es el diseño que NovaPay recomienda como arquitectura de referencia para una suscripción de producción sin restricciones de cuota, documentado aquí con el mismo rigor que los componentes implementados.

## Contexto de la restricción actual (nota secundaria, no el argumento central)

App Service en tier Standard (S1, el tier realmente desplegado de `api-novapay-{env}`) no soporta zone-redundancy — requiere Premium v2/v3, verificado en la documentación oficial de Microsoft Learn. El entregable final de U3 (Tabla 3, ajuste #6) documentó empíricamente que la suscripción Free Trial usada para la evidencia de este proyecto no tenía cuota disponible para Premium v3 en el momento de esa entrega. Esta es una circunstancia de la suscripción usada para la evidencia académica, no una limitación del diseño arquitectónico en sí.

## Decisión

Documentar el diseño objetivo de arriba con el mismo nivel de detalle que los mecanismos que sí se implementan (ADR-04, ADR-06), y no reintentar el upgrade de plan en esta suscripción para esta entrega — replicando el mismo patrón de transparencia ya usado con Business Critical de Azure SQL en U3: la arquitectura de referencia se documenta completa; la implementación real se ajusta a lo que la suscripción de evidencia permite, y esa diferencia se explica, no se oculta ni se disfraza de limitación de diseño.

## Consecuencias

**Positivas**
- El diseño objetivo queda documentado con el mismo rigor que los mecanismos implementados, evitando que la Sección 3 dependa únicamente de lo alcanzable en una suscripción Free Trial para demostrar profundidad arquitectónica.
- Evita repetir un intento de upgrade con alta probabilidad de fallo ya conocida (ahorra tiempo de la entrega).
- Mantiene coherencia con el patrón de documentación de restricciones de suscripción ya establecido y evaluado positivamente en la entrega anterior.

**Negativas**
- La cuota no se reverifica en esta entrega — se hereda como supuesto de U3, no como hecho confirmado de nuevo.
- Sin este componente implementado, la Sección 3 depende de ADR-04 (Function App) y ADR-06 (SQL) para su evidencia real; `api-novapay-{env}` queda sin ningún componente de alta disponibilidad con evidencia funcional propia — coherente con que tampoco tiene código de aplicación desplegado (ver ADR-03).

## Alternativas descartadas

- Intentar el upgrade a Premium v3 igualmente para verificar si la cuota cambió: se dejó como opción explícita al usuario, quien decidió no darle prioridad frente al riesgo de repetir el mismo bloqueo ya documentado.
