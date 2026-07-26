# Módulo `observability`

Log Analytics Workspace centralizado y grupo de acción de alertas. Recibe, vía `monitored_resource_ids`, los IDs de recursos de las capas 1 y 2 y les configura *diagnostic settings* genéricos (todos los logs y métricas) sin que este módulo necesite conocer el tipo de cada recurso.

## Entradas principales
`monitored_resource_ids` (mapa nombre -> ID, provisto por la composición raíz), `retention_in_days` (30 en dev, ≥ 1826 en prod).

Capa 3 (observabilidad): se conecta transversalmente a las capas 1 y 2, nunca al revés.
