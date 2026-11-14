# Schema for populations.tsv

Each row is a population type: base humans, and the made, modified and virtual kinds a
game can come to hold. A type is only numbers. The code never asks what a type is, only
what it needs and how its numbers behave, so the columns below are the whole of a type's
difference from another (`POPULATION_MODEL.md`, "A population is what it needs" and
"Kinds of population").

The `Default` row holds base humans' values, and the other types inherit them until their
own content is written, which comes with the first game that holds them
(`POPULATION_MODEL.md`, "What is built and what waits").


## Table Data

- age_group_widths — ARRAY[FLOAT] in years, seven values: how long the type spends in each of its
  first seven age groups. The eighth, oldest age group has no upper bound. A population passes an
  age group's members on to the next as a life table at the age group's death rate has them leave
  it alive, one over its width where none die, which is the whole of aging, so the widths are what
  make a type long-lived or quick to age. A population's pace of aging divides its adults' and
  elders' widths. Base humans' age groups are 0-4, 5-14, 15-24, 25-39, 40-54, 55-64, 65-79 and 80+
  (`POPULATION_MODEL.md`, "Demographics").
- first_adult_age_group — INT, the first age group whose members are adults. The age groups below it
  are the young, so a type with no youth, such as one made as an adult, has 0.
- first_elder_age_group — INT, the first age group whose members are elders.
- birth_weights — ARRAY[FLOAT], eight values: the births per head of each age group, relative
  to the others. A population's fertility level scales them. Zero wherever an age group bears
  no children.
- starvation_rate — FLOAT per year: the deaths per head a year that the type suffers on top
  of its death rates with no life support at all. Going without life support kills on a time
  constant the type sets: weeks for a biological body, far longer for a machine.
- starvation_threshold — FLOAT, between 0 and 1: the share of its life-support needs met
  below which the type starts to starve. Starvation rises with the square of the shortfall
  below it. Births fall as the share falls from 1 toward it, with the square of the shortfall
  over the gap between the two, to none at it (`POPULATION_MODEL.md`, "Demographics").

The next columns are the type's three slow responses (`POPULATION_MODEL.md`, "Demographics"). Each
moves a population's rates toward what its satisfaction of its needs implies: the rate it has
when they are met, times each satisfaction to the power of minus an elasticity, flat at the
want and steepest far below it. A positive elasticity raises the rate as the need goes short,
and a negative one lowers it. A population whose people hold their means unevenly (its
inequality, `facilities_populations.tsv`) takes the average over its deciles.

- mortality_need — TABLE_ROW `needs.tsv`, the need whose satisfaction sets the death rates.
  Blank holds them at their seeds.
- served_mortalities — ARRAY[FLOAT] per year, eight values: each age group's deaths per head
  with the need met, at a frailty of one.
- mortality_elasticities — ARRAY[FLOAT], eight values: how steeply each age group's death rate
  rises as the need goes short, the exponent above. The young respond most.
- mortality_floor — FLOAT, the satisfaction below which going further without kills no
  faster.
- mortality_response_time — FLOAT in years: how long the death rates take to move most of
  the way to what a changed satisfaction implies, the time constant of their relaxation.
- fertility_needs — ARRAY[TABLE_ROW] `needs.tsv`, the needs whose satisfactions set the
  fertility. Blank holds it at its seed. Base humans' are learning, whose lack raises it,
  and shelter, whose lack, crowding, lowers it.
- served_fertility — FLOAT per year, the fertility with the needs met, at a fecundity and a pace
  of aging of one: births per head, each weighted by `birth_weights`.
- fertility_elasticities — ARRAY[FLOAT], one for each of `fertility_needs`: how steeply the
  fertility moves as the need goes short, negative where it falls.
- fertility_floor — FLOAT, the satisfaction below which going further without moves the
  fertility no further.
- fertility_response_time — FLOAT in years, as `mortality_response_time`, for the fertility.
- participation_needs — ARRAY[TABLE_ROW] `needs.tsv`, the needs whose satisfactions set the
  participation, the most of its able hours a population offers. Blank holds it at its seed.
  Default `HEALTH`: the sick work less.
- served_participation — FLOAT, the participation with the needs met. Default `0.651`, the
  USA's seed, the best-served polity's.
- participation_elasticities — ARRAY[FLOAT], one for each of `participation_needs`: how
  steeply the participation moves as the need goes short, negative where it falls. Default
  `-0.15`.
- participation_floor — FLOAT, the satisfaction below which going further without moves the
  participation no further. Default `0.01`.
- participation_response_time — FLOAT in years, as `mortality_response_time`, for the
  participation. Default `5 y`.
- spending_rate — FLOAT per year: the share of its wealth a population spends in a year on
  its wants. Its deciles spend it on their existence wants first, all of it if they take
  it, and the rest over their other wants in the shares `wants.tsv` sets
  (`POPULATION_MODEL.md`, "Work and pay"). Its inverse is how many years of spending the
  wealth seeded in `facilities_populations.tsv` holds. Default `1/y`.
- work_resource — TABLE_ROW `resources.tsv`, the resource the type's work makes. Default
  `LABOR`, which every operation draws (`POPULATION_MODEL.md`, "Work and pay").
- work_stage_weights — ARRAY[FLOAT], three values, young, adults and elders: how much of a
  working head each member of a life stage counts as. Default `0;1;0.2`.
- work_hours — FLOAT in hours per year, the hours a working head works. A population's able
  hours are its weighted heads times these hours times its participation
  (`facilities_populations.tsv`), and staff on loan work them in full. Its deciles offer them
  down to their spending per hour lived. Default `1800 h/y`.

The last columns are the type's schooling, the years of school its people hold, gained by the
young and carried as they age, and what it makes of an hour (`POPULATION_MODEL.md`, "Productivity
and schooling"). An hour of a population makes its type's factor times the know-how of the place
it works (`facilities_populations.tsv`) times e to the return times its workforce's years of
schooling past the reference, and a place's know-how closes on the frontier, faster as the types
working there that move it (`catch_up_time`) are better schooled.

- schooling_need — TABLE_ROW `needs.tsv`, the need whose satisfaction gains the young their
  schooling. Blank: the type gains none and holds what it was seeded with. Default `LEARNING`.
- schooling_rates — ARRAY[FLOAT], eight values: the years of schooling each age group gains a
  year with the need met. The last age group, which has no width, gains none. An age group that
  gains holds what its people will carry out of it, since its people leave it at one rate however
  long they have been in it. Default `0;0.95;0.43;0;0;0;0;0`: 9.5 years by 15 and 13.8 by 25, what
  the USA's young held in 2015, from recall.
- schooling_elasticity — FLOAT, how steeply the schooling gained falls as the need goes short:
  the rates times each decile's satisfaction of the need to this power, averaged over the
  deciles, as the slow responses average theirs. One gains in proportion to the need met. Default
  `0.27`, from recall: India's young, served about a fifth of the learning the USA's are, held
  about two thirds of their years.
- schooling_return — FLOAT per year of schooling: how much more an hour makes for each year its
  workforce holds, e to it times the years, the Mincerian return. Zero leaves the hour at the
  know-how, whatever the schooling, as for a made type, which counts as schooled to its
  reference. Default `0.1/y`.
- reference_schooling — FLOAT in years: the workforce's schooling at which an hour makes the
  know-how, its people weighted as `work_stage_weights` counts them. Base humans' is the USA's as
  seeded for 2015, at whose know-how of one an hour makes what the recipes assume. Default
  `13.57 y`.
- catch_up_time — FLOAT in years: how fast the know-how of the place a population works closes on
  the frontier, one, the recipes' own. Each year it closes a share of its gap, what its workforce's
  schooling makes of an hour against the reference schooling over this time, so a population
  schooled to the reference closes about a thirtieth of its gap a year at the default; where
  several types work, each type that moves know-how weighs in by the hours its workforce could
  work. `inf`, as for a made type: its workforce neither moves the place's know-how nor weighs in
  its pace. Default `30 y`, a guess.
- productivity_factor — FLOAT: what an hour of the type does of a person's at the frontier, at its
  reference schooling, so that its productivity is this times its place's know-how and what its
  schooling gives; a type that technology improves has its factor raised (`POPULATION_MODEL.md`,
  "Owned populations", its work). Default `1`.

The last columns are a made type's: the good its individuals are made of until they are
commissioned where they will live (`POPULATION_MODEL.md`, "Owned populations"). Blank for a type
that is born.

- good — TABLE_ROW `resources.tsv`, the manufactured good a made type's individuals are made of,
  traded and moved as any good until its owner commissions them: capital commissions as many as
  their work would pay for, as it builds plant. Blank for a type that is born.
- good_qty — FLOAT in tonnes: how much of its good one individual is made of, what a
  commissioning draws for each.
- commissioning_time — FLOAT in years: how long a commissioning of a type's room takes on its
  schedule, as a module's `build_time` is for its buildouts.


## Notes

1. The number of age groups, eight, is the model's and not a type's (`POPULATION_MODEL.md`,
   "Demographics"). What a type sets is where its age groups fall in its own lifetime.
2. A population's own death rates, fertility, inequality, wealth, schooling, know-how and
   participation are state, seeded per facility in `facilities_populations.tsv`, and so are how
   unevenly its wages and its dividends reach its people. The death rates, fertility and
   participation then move as above; the wealth stays as it is through births and deaths, a death
   leaving its share to the survivors; the schooling moves with its people, the born holding none
   and the dead taking their age group's; the know-how closes on the frontier; and the inequality
   moves with how unevenly what the population is paid reaches it (`FINANCIAL_MODEL.md`, "The
   residents and inequality").
3. Base humans' response columns are fitted on the 2017 cross-section of countries by
   `tests/calibration/seed_demography.py --fit`, as a person's curve over each country's ten
   deciles, each holding what its governments pay alike and the rest at its inequality
   (`EARTH_CALIBRATION.md`, "Population"). The floors and response times are not fitted, and
   neither are the fertility's response to crowding, the participation's response and the
   schooling's, whose values are from recall, or the catch-up time, a guess.
4. What a type needs, and where it can live, are its wants (`wants.tsv`): room is the want of its
   shelter need, a draw on the habitation its environments' housing makes, and an individual that
   takes less room wants less of it (`POPULATION_MODEL.md`, "Where populations live").
