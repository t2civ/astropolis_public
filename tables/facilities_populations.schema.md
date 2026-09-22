# Schema for facilities_populations.tsv

This Entity x Entity table defines the age structure and vital rates of each population
at facilities at simulation start in 2015. How many a facility holds of each type is
`population` in `facilities.tsv`; this table says how they are spread over the type's
eight age buckets and how fast they die and bear children. Population types are described
in `populations.schema.md`, and the model in `POPULATION_MODEL.md` ("Demographics").


## Table Data

The data type is ARRAY[FLOAT]; each cell holds 17 values delimited by semicolons:

- 8 values — each age bucket's share of the population, in the order of the type's buckets.
- 8 values, per year — the deaths per head in each bucket.
- 1 value, per year — the fertility: births per head, each head weighted by its bucket's
  `birth_weights` in `populations.tsv`.

The rates carry an inline `/y`. A cell must be present for every population that
`facilities.tsv` seeds, and is empty otherwise.


## Notes

1. The table is generated, not hand-edited: `tests/calibration/seed_demography.py` derives
   it from UN World Population Prospects 2024 for 2015, reading the type's buckets and birth
   weights from `populations.tsv`, so it follows them when they change.
2. An agency takes its polity's cell.
3. The shares need not sum exactly to one; the game starts each bucket at its share of the
   facility's population, rounded down, and gives the remainder to the largest bucket.
