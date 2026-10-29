# Schema for wants.tsv

Each row is a want: what one individual of a population type draws to fill one of its needs
(`needs.tsv`) when nothing holds it back. A want of zero is no want, and a type has only the
needs it has rows for. Wants are universal, the same for a type in every polity: a want is a
saturation level, and what differs from place to place is what a population gets
(`POPULATION_MODEL.md`, "Needs").

A want's recipe is written as an operation's is (`operations.schema.md`, "Flow Fields"),
with its target lists and none of its driver lists. Each of the residents' deciles buys it
at local prices from its spending, up to its share of their head count in each life stage
times `stage_weights`: its existence wants first, as one bundle, then each input of each other
want with its share of the want's `spending_share` of what is left, the input's share by its
value at the facility's long prices, its local prices averaged over a decade, and its substitution
group one input, valued at its members' soft minimum ("Work and pay" in `POPULATION_MODEL.md`). What they buy of each input is a draw of its own in the facility's
clear, shared in a shortage with the operations', and what they give off follows what they drew
("The residents' draw, as built" there).


## Table Data

- population — The population type (`populations.tsv`).
- need — The need it fills (`needs.tsv`). A type may fill one need with more than one want,
  one per unit its satisfiers come in.
- stage_weights — ARRAY[FLOAT], three values: how much of the want an individual of each life
  stage (young, adults, elders; `Enums.LifeStages`) draws, relative to the rates. Default
  `1;1;1`.
- spending_share — FLOAT, the share of what a decile has left after its existence wants that
  it spends on this want, none past the want. Blank for an existence want, which comes
  first. The shares are relative: a type's are scaled to sum to one. Where public provision buys
  part of a want, its share shrinks with what is left to the decile to buy, and the others take up
  what it no longer spends.
- public_share — FLOAT, the share of the want that a polity's public provision buys for every
  decile alike, as far as the line of its government treasury's budget for it goes
  (`FINANCIAL_MODEL.md`, "The treasuries' budgets"); each decile buys the rest. Blank: none, a
  private want. An existence want takes none.
- spread — FLOAT, how readily its substitution group's members stand in for one another: the
  share of what its cheapest member costs, for what it fills, over which their shares change
  e-fold. Wide where one form stands in for another only in part. Blank: 0.2.
- in_inventory, in_inventory_rates, in_inventory_groups, in_inventory_mixes — What it draws from
  inventory, at per-individual rates, and its substitution group: its members, each at the rate
  that fills the want alone and so standing in for the others at what it costs for what it fills,
  split among them by those costs over the want's `spread`, each weighed by its mix where they
  cost alike (`POPULATION_MODEL.md`, "Services, in person and virtual"). A blank mix is 1. A want
  has one group at most, its members in one unit. The rates default to
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
   and education at the flat of the cross-section of countries, where more stops buying longer lives or
   fewer births (`POPULATION_MODEL.md`, "Needs"); and the other services at the USA's seeded
   output per head.
4. Base humans' spending shares are each want's value per head at start prices, over the
   world's life stages in 2015, as a share of all but their existence want's.
5. Base humans' order is two wants, public administration, policing and the courts, which the
   state provides, and law and insurance, which households buy. Their public shares are about
   the most of each want any state provides in 2015: nearly all of public administration, nine
   tenths of schooling and a little less of health care, from recall.
