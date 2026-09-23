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
- starvation_threshold — FLOAT, the share of its life-support needs met below which the
  type starts to starve. Starvation rises with the square of the shortfall below it.

The remaining columns are the type's two slow responses (P12 in `POPULATION_MODEL.md`). Each
moves a population's rates toward what its satisfaction of one need implies: the rate the
type has when the need is met, times the satisfaction to the power of minus an elasticity,
flat at the want and steepest far below it. A population whose people are served unevenly
(its spread, `facilities_populations.tsv`) takes the average over its classes.

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


## Notes

1. The number of age buckets, eight, is the model's and not a type's (P1 in
   `POPULATION_MODEL.md`). What a type sets is where its buckets fall in its own lifetime.
2. A population's own death rates, fertility and spread are state, seeded per facility in
   `facilities_populations.tsv`. The death rates and fertility then move as above; nothing
   moves the spread yet.
3. Base humans' response columns are fitted on the 2017 cross-section of countries by
   `tests/calibration/seed_demography.py --fit` (`EARTH_CALIBRATION.md`, "Population"). The
   floors and response times are not fitted.
4. What a type needs, and where it can live, are its wants (`wants.tsv`): room is the want
   of its shelter need, a draw on the habitation its environments' housing makes, and an
   individual that takes less room wants less of it (P6 in `POPULATION_MODEL.md`).
