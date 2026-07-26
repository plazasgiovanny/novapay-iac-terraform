# Módulo `networking`

Aprovisiona la VNet spoke de NovaPay: subredes por dominio (aplicación, integración, datos, pública), un NSG por subred en modo *deny-by-default*, y el peering hacia la VNet hub.

## Entradas principales
- `vnet_cidr`, `subnets` (mapa de CIDR + reglas permitidas por subred), `hub_vnet_id`.

## Salidas
- `subnet_ids`: consumido por `security-keyvault`, `data-sql` y `compute-appservice` para integración de red y Private Endpoints.
- `vnet_id`: consumido por `observability` para diagnostic settings.
- `nsg_ids`: expuesto para diagnóstico manual; ningún otro módulo lo consume todavía (posible extensión futura de `observability`).

No depende de ningún otro módulo (capa 1: red y seguridad base — ver sección 3.3 del documento).
