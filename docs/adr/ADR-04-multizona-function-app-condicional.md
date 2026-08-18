# ADR-04: Multi-zona condicional y reversible en el Function App

**Estado:** Aceptada — 2026-08-15
**Sección U4 afectada:** 3. Escalabilidad y Alta Disponibilidad
**Relacionada:** ADR-03 (mismo principio: no sacrificar el escalado a cero), ADR-05 (multi-zona descartada en App Service)

## Contexto

La Sección 3 de U4 exige **diseñar** (no necesariamente implementar de forma permanente) "Multi-zona o equivalente". Se verificó con `az functionapp list-flexconsumption-locations --zone-redundant=true` contra la suscripción real que **`centralus` sí soporta zone-redundancy en Flex Consumption**, GA, sin costo adicional por instancia. Sin embargo, la documentación oficial confirma que habilitarla fuerza un mínimo de **2 instancias always-ready por función/grupo**, lo que rompe el escalado a cero: un Function App que hoy escala a cero cuando está inactivo pasaría a facturar una línea base continua.

Esto entra en tensión directa con la ventaja central del modelo serverless que el propio proyecto ya defendió en la Reflexión Técnica de U3 (§7.1): "el modelo de pago por ejecución evita sostener capacidad reservada para un tráfico que, la mayor parte del mes, no se materializa". Aplicar zone-redundancy de forma permanente sin más análisis contradiría ese argumento ya entregado y calificado.

## Decisión

Diseñar la arquitectura zone-redundant como **estado objetivo documentado** (target-state), y activar `zone-redundant=true` de forma real **solo el tiempo necesario para capturar evidencia**, desactivándolo inmediatamente después. Se documenta como una **política condicional**: la activación se reservaría, en un escenario de producción real, para ventanas de alto tráfico conocido (quincena, campañas con bancos aliados — el mismo patrón que ya narra la Lectura Fundamental de U4 sobre ScaleNow), no como postura permanente.

**Mecanismo concreto (cierra hallazgo de "promesa sin mecanismo" de la revisión arquitectónica)**:

0. **Diseño de almacenamiento**: cada instancia (`func-novapay-pagos-{env}` y `func-novapay-pagos-canary-{env}`) tiene su **propia** cuenta de almacenamiento host dedicada — no comparten una sola cuenta entre las dos. Es una decisión explícita de esta entrega (no heredada), consistente con el mismo patrón de "alcance por recurso puntual, no compartido" que ya usa el proyecto para IAM (Tabla 3, Entrega 1) y para los roles de Service Bus. Esto es lo que hace válido el aislamiento por plan del paso 2: activar zone-redundancy en una instancia no toca ni el plan ni el almacenamiento de la otra.
1. **Prerrequisito**: la cuenta de almacenamiento host de la instancia objetivo debe usar SKU `Standard_ZRS` (zone-redundant); si no la usa, se actualiza antes de activar.
2. **Verificación previa del objetivo**: antes de ejecutar el comando de activación, se consulta el peso actual del backend pool de APIM (mismo mecanismo ya usado en la Sección 1/2 antes de desplegar) para confirmar cuál instancia está en 0% — evita que un operador apunte por error al plan de la instancia vigente, especialmente relevante porque los roles estable/candidata rotan entre ciclos de despliegue (Sección 2).
3. **Activación**: `az functionapp plan update --ids $(az functionapp show --resource-group <rg> --name <app> --query "properties.serverFarmId" -o tsv) --set zoneRedundant=true`, sobre el plan de la instancia confirmada en el paso 2. **Importante**: este cambio provoca un reinicio del Function App (downtime breve) — por eso no puede activarse durante una ventana de canary en curso (Sección 2); se coordina en un momento sin rampa activa.
4. **Verificación de evidencia**: `az rest --method get --url "<resource-id>/instances?api-version=2024-04-01" --query "value[].{machineName:properties.machineName, physicalZone:properties.physicalZone}"` — confirma instancias repartidas en al menos dos zonas físicas distintas.
5. **Reversión**: mismo comando de activación con `zoneRedundant=false`, también con reinicio breve, coordinado fuera de ventana de canary.

**Encuadre como experimento controlado**: este ciclo activar→verificar→desactivar es, en esencia, la práctica de **Chaos Engineering** que describe la Lectura Fundamental de U4 (§3.6) — no se trata de "creer" que la resiliencia zonal funciona, sino de provocarla de forma controlada y medirla, igual que ScaleNow simula caída de zona para validar failover.

## Consecuencias

**Positivas**
- Da evidencia real y verificable (no solo descrita) sin asumir el costo operativo de forma indefinida.
- El propio trade-off (elasticidad vs. resiliencia zonal) es un argumento arquitectónico sustantivo, directamente reutilizable en la Sección 7 (trade-offs) y coherente con la reflexión ya escrita en U3.

**Negativas**
- La evidencia capturada refleja un estado transitorio, no la postura real de producción — debe explicarse así con toda claridad en el documento, para no sugerir (incorrectamente) que el sistema corre permanentemente zone-redundant.
- Requiere un paso operativo adicional (activar → capturar evidencia → desactivar) que no forma parte del flujo de despliegue normal.
- Activar y desactivar zone-redundancy **reinicia el Function App** (downtime breve) — el ciclo debe coordinarse fuera de cualquier ventana de canary activa (Sección 2), nunca en paralelo.

## Alternativas descartadas

- Dejarlo activado de forma permanente: rompe el escalado a cero de forma indefinida, contradiciendo la reflexión ya entregada en U3.
- No activarlo nunca (solo diseño, cero evidencia real): más simple, pero deja la Sección 3 sin evidencia funcional, un requisito explícito de la actividad ("evidencia funcional obligatoria").
