# Schema for populations.tsv

Each row is a population type: base humans, and the made, modified and virtual kinds a
game can come to hold. A type is only numbers. The code never asks what a type is, only
what it needs and how its numbers behave, so the columns below are the whole of a type's
difference from another (`POPULATION_MODEL.md`, "A population is what it needs" and
"Kinds of population").

The `Default` row holds base humans' values, and the other types inherit them until their
own content is written, which comes with the first game that holds them
(`POPULATION_MODEL.md`, "From exploration to plan", step 6).


## Table Data

- bucket_widths — ARRAY[FLOAT] in years, seven values: how long the type spends in each of
  its first seven age buckets. The eighth, oldest bucket has no upper bound. Each unit of
  time a population moves on the share of a bucket's members that is one over the bucket's
  width, which is the whole of aging, so the widths are what make a type long-lived or quick
  to age. Base humans' buckets are 0-4, 5-14, 15-24, 25-39, 40-54, 55-64, 65-79 and 80+ (P1).
- first_adult_bucket — INT, the first bucket whose members are adults. The buckets below it
  are the young, so a type with no youth, such as one made as an adult, has 0.
- first_elder_bucket — INT, the first bucket whose members are elders.
- birth_weights — ARRAY[FLOAT], eight values: the births per head of each bucket, relative
  to the others. A population's fertility level scales them. Zero wherever a bucket bears
  no children.
- starvation_rate — FLOAT per year: the deaths per head a year that the type suffers on top
  of its death rates with no life support at all. Going without life support kills on a time
  constant the type sets: weeks for a biological body, far longer for a machine.
- starvation_threshold — FLOAT, between 0 and 1: the share of its life-support needs met
  below which the type starts to starve. Starvation rises with the square of the shortfall
  below it. Births fall as the share falls from 1 toward it, with the square of the shortfall
  over the gap between the two, to none at it (`POPULATION_MODEL.md`, "Demographics").

The next columns are the type's three slow responses (P12 in `POPULATION_MODEL.md`). Each
moves a population's rates toward what its satisfaction of its needs implies: the rate it has
when they are met, times each satisfaction to the power of minus an elasticity, flat at the
want and steepest far below it. A positive elasticity raises the rate as the need goes short,
and a negative one lowers it. A population whose people are served unevenly (its spread,
`facilities_populations.tsv`) takes the average over its classes.

- mortality_need — TABLE_ROW `needs.tsv`, the need whose satisfaction sets the death rates.
  Blank holds them at their seeds.
- served_mortalities — ARRAY[FLOAT] per year, eight values: each bucket's deaths per head
  with the need met.
- mortality_elasticities — ARRAY[FLOAT], eight values: how steeply each bucket's death rate
  rises as the need goes short, the exponent above. The young respond most.
- mortality_floor — FLOAT, the satisfaction below which going further without kills no
  faster.
- mortality_response_time — FLOAT in years: how long the death rates take to move most of
  the way to what a changed satisfaction implies, the time constant of their relaxation.
- fertility_need — TABLE_ROW `needs.tsv`, the need whose satisfaction sets the fertility.
  Blank holds it at its seed.
- served_fertility — FLOAT per year, the fertility with the need met: births per head, each
  weighted by `birth_weights`.
- fertility_elasticity — FLOAT, how steeply the fertility rises as the need goes short.
- fertility_floor — FLOAT, the satisfaction below which going further without adds no
  births.
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
  its wants. Its classes spend it on their existence wants first, all of it if they take
  it, and the rest over their other wants in the shares `wants.tsv` sets
  (`POPULATION_MODEL.md`, "Work and pay"). Its inverse is how many years of spending the
  wealth seeded in `facilities_populations.tsv` holds. Default `1/y`.
- work_resource — TABLE_ROW `resources.tsv`, the resource the type's work makes. Default
  `LABOR`, which every operation draws (`POPULATION_MODEL.md`, "Work and pay").
- work_stage_weights — ARRAY[FLOAT], three values, young, adults and elders: how much of a
  working head each member of a life stage counts as. Default `0;1;0.2`.
- work_hours — FLOAT in hours per year, the hours a working head works. A population's able
  hours are its weighted heads times these hours times its participation
  (`facilities_populations.tsv`), and staff on loan work them in full. Its classes offer them
  down to their spending per hour lived. Default `1800 h/y`.


## Notes

1. The number of age buckets, eight, is the model's and not a type's (P1 in
   `POPULATION_MODEL.md`). What a type sets is where its buckets fall in its own lifetime.
2. A population's own death rates, fertility, spread, wealth and participation are state,
   seeded per facility in `facilities_populations.tsv`. The death rates, fertility and
   participation then move as above, and the wealth only with the head count, a death taking
   its share and a birth bringing the average; nothing moves the spread yet.
3. Base humans' response columns are fitted on the 2017 cross-section of countries by
   `tests/calibration/seed_demography.py --fit` (`EARTH_CALIBRATION.md`, "Population"). The
   floors and response times are not fitted, and neither is the participation's response,
   whose values are from recall.
4. What a type needs, and where it can live, are its wants (`wants.tsv`): room is the want
   of its shelter need, a draw on the habitation its environments' housing makes, and an
   individual that takes less room wants less of it (P6 in `POPULATION_MODEL.md`).
