# Schema for resources.tsv

Resources are described in `resources.descriptive.md`.


## Fields

- name (1st column) — Resource name per data table instructions.
- resource_class — For GUI only; one of ENERGY, ORES, VOLATILES, MATERIALS, MANUFACTURED, BIOLOGICAL, or SERVICES, corresponding to groupings in `resources.descriptive.md`.
- commodity — BOOL value (default TRUE); specifies whether the resource is traded as a commodity. (TODO: Possible deprecation; redundant with missing trade_class.)
- consumed — BOOL value (default FALSE); specifies whether the resource is absorbed into some local process or mechanic (never moved; exists only transiently).
- trade_class — For resources that are tradable, specifies shipment handling. CYBER is a special case that is traded on a common system-wide market. Blank/-1 means that the resource cannot be traded.
- storage_class — One of storage classes defined in storage_classes.tsv. Describes the physical storage and transport infrastructure required for the resource. Empty for service resources.
- trade_unit — Resource unit for trade and price display.
- start_price — INT in USD per `trade_unit` (the row's `trade_unit`). Imported and used at game start to seed market prices, at the 2015 vintage the simulation starts from. Being an integer, small values round; the float sources and the 2015 / 2025 / 2035 price targets are kept in the development repository's `EARTH_CALIBRATION.md`.
- is_extraction — TRUE ("x") for extractable resources.
- is_volatile — TRUE ("x") for volatile resources.
- disposal_sink — `ATMOSPHERE` or `SURFACE` (`Enums.DisposalSinks`): the body stratum that receives this resource when a facility disposes of surplus from a full storage class. Required on every `is_extraction` resource that has a `storage_class`, and blank on all others (only extractable resources can live in a stratum). Choose by phase at Earth ambient: gases to `ATMOSPHERE`; water, liquids and solids to `SURFACE`. A facility without that stratum (e.g. a spacecraft) disposes of the resource out of the simulation.
