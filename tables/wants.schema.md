# Schema for wants.tsv

Each row is a want: what one individual of a population type draws to fill one of its needs
(`needs.tsv`) when nothing holds it back. A want of zero is no want, and a type has only the
needs it has rows for. Wants are universal, the same for a type in every polity: a want is a
saturation level, and what differs from place to place is what a population gets
(`POPULATION_MODEL.md`, "Needs").

A want's recipe is written as an operation's is (`operations.schema.md`, "Flow Fields"),
with its target lists and none of its driver lists. Each of the residents' classes buys it
at local prices from its spending, up to its share of their head count in each life stage
times `stage_weights`: its existence wants first, as one bundle, then each input of each other
want with its share of the want's `spending_share` of what is left, the input's share by its
value at start prices ("Work and pay" in `POPULATION_MODEL.md`). What they buy of each input is
a draw of its own in the facility's clear, shared in a shortage with the operations', and what
they give off follows what they drew (P11 there).


## Table Data

- population — The population type (`populations.tsv`).
- need — The need it fills (`needs.tsv`). A type may fill one need with more than one want,
  one per unit its satisfiers come in.
- stage_weights — ARRAY[FLOAT], three values: how much of the want an individual of each life
  stage (young, adults, elders; `Enums.LifeStages`) draws, relative to the rates. Default
  `1;1;1`.
- spending_share — FLOAT, the share of what a class has left after its existence wants that
  it spends on this want, none past the want. Blank for an existence want, which comes
  first. The shares are relative: a type's are scaled to sum to one.
- in_inventory, in_inventory_rates, in_inventory_groups — What it draws from inventory, at
  per-individual rates, and its substitution group: members one for one, each at the rate that
  fills the want alone, split among them by their local prices, a member taking none where the
  cheapest is a fifth below its own price. A want has one group at most, and only an
  existence want has one. The rates default to
  `t/y`; a resource that is not mass carries its unit (`h/y` for a service, `h/h` for
  habitation, `MW` for electricity).
- in_atmos, in_atmos_rates — What it draws from the atmosphere, free where there is one and
  from inventory where the facility runs in closed cycle.
- out_inventory, out_inventory_rates; out_atmos, out_atmos_rates — What it gives off. Outputs
  follow the share of the want drawn.


## Notes

1. A want's inputs share a unit, or are goods counted by mass: the share of it drawn sums
   them by quantity. Satisfiers of one need in different units are separate wants.
2. Base humans' existence want is their sustenance: food, water and air. Its food is one
   substitution group, crops, animal products or packaged meals one for one by the kilogram,
   so they eat the cheapest. Animal products and packaged meals are also a want of their own
   beyond subsistence, under goods, and the biowaste of the food is split between the two by
   mass.
3. The rates are sizing, recorded in the development repository's `EARTH_CALIBRATION.md`
   ("Base humans' wants"): the food, water, air, goods, private cars and household
   electricity of the basket `URBAN_OPERATIONS` drew per person before the model; healthcare
   and education at the flat of R20's cross-section, where more stops buying longer lives or
   fewer births (P13 in `POPULATION_MODEL.md`); and the other services at the USA's seeded
   output per head.
4. Base humans' spending shares are each want's value per head at start prices, over the
   world's life stages in 2015, as a share of all but their existence want's.
