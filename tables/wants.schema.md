# Schema for wants.tsv

Each row is a want: what one individual of a population type draws to fill one of its needs
(`needs.tsv`) when nothing holds it back. A want of zero is no want, and a type has only the
needs it has rows for. Wants are universal, the same for a type in every polity: a want is a
saturation level, and what differs from place to place is what a population gets
(`POPULATION_MODEL.md`, "Needs").

A want's recipe is written as an operation's is (`operations.schema.md`, "Flow Fields"),
with its target lists and none of its driver lists. Each interval the residents of a type
draw it through the facility's clear as one more consumer, at their head count in each life
stage times `stage_weights`, each input or substitution group at its own fill, at their
need's tier (P11 in `POPULATION_MODEL.md`). What they draw books as their upkeep
(`POPULATION_UPKEEP` in `line_items.tsv`).


## Table Data

- population — The population type (`populations.tsv`).
- need — The need it fills (`needs.tsv`). A type may fill one need with more than one want,
  one per unit its satisfiers come in.
- stage_weights — ARRAY[FLOAT], three values: how much of the want an individual of each life
  stage (young, adults, elders; `Enums.LifeStages`) draws, relative to the rates. Default
  `1;1;1`.
- in_inventory, in_inventory_rates, in_inventory_groups — What it draws from inventory, at
  per-individual rates, and its substitution groups, as an operation's. The rates default to
  `t/y`; a resource that is not mass carries its unit (`/y` for a service unit, `MW` for
  electricity).
- in_atmos, in_atmos_rates — What it draws from the atmosphere, free where there is one and
  from inventory where the facility runs in closed cycle.
- out_inventory, out_inventory_rates; out_atmos, out_atmos_rates — What it gives off. Outputs
  follow the share of the want drawn.


## Notes

1. A want's inputs share a unit, or are goods counted by mass: the share of it drawn sums
   them by quantity. Satisfiers of one need in different units are separate wants.
2. Base humans' existence want is their sustenance: food, water and air. Its food is one
   substitution group, which they eat whichever members are in stock.
3. The rates are sizing, recorded in the development repository's `EARTH_CALIBRATION.md`
   ("Base humans' wants"): the food, water, air, goods, private cars and household
   electricity of the basket `URBAN_OPERATIONS` drew per person before the model; healthcare
   and education at the flat of R20's cross-section, where more stops buying longer lives or
   fewer births (P13 in `POPULATION_MODEL.md`); and the other services at the USA's seeded
   output per head.
