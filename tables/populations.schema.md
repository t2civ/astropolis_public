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

- carrying_capacity_group — The environment the type lives in (`carrying_capacity_groups.tsv`),
  whose room housing modules supply.
- carrying_capacity_group2 — A second environment it can also live in, or empty.
- required_space — Room one individual takes, relative to a base human's 1.
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


## Notes

1. The number of age buckets, eight, is the model's and not a type's (P1 in
   `POPULATION_MODEL.md`). What a type sets is where its buckets fall in its own lifetime.
2. A population's own death rates and fertility are state, seeded per facility in
   `facilities_populations.tsv`.
