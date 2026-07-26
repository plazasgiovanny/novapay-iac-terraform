# Módulo `networking`

Aprovisiona la VNet spoke de NovaPay: subredes por dominio (aplicación, integración, datos, pública), un NSG por subred en modo *deny-by-default*, y el peering hacia la VNet hub.

## Entradas principales
- `vnet_cidr`, `subnets` (mapa de CIDR + reglas permitidas por subred), `hub_vnet_id`.

## Salidas
- `subnet_ids`: consumido por `compute-appservice` y `data-sql` para integración de red.
- `nsg_ids`, `vnet_id`: consumidos por `observability` para diagnostic settings.

No depende de ningún otro módulo (capa 1: red y seguridad base — ver sección 3.3 del documento).
