# Schema for facilities_populations.tsv

This Entity x Entity table defines the age structure, vital rates, inequality and its spreads,
wealth and participation of each population at facilities at simulation start in 2015. How many a facility holds of each
type is `population` in `facilities.tsv`; this table says how they are spread over the
type's eight age groups, how fast they die and bear children, how unevenly they
hold their means and are paid, what they hold and how much they work. It is the populations' starting state: from the first interval their death rates,
fertility and participation move with what they get, and their inequality with how unevenly
what they are paid reaches them (`populations.schema.md`). Population types are described
in `populations.schema.md`, and the model in `POPULATION_MODEL.md` ("Demographics").


## Table Data

The data type is ARRAY[FLOAT]; each cell holds 22 values delimited by semicolons:

- 8 values — each age group's share of the population, in the order of the type's age groups.
- 8 values, per year — the deaths per head in each age group.
- 1 value, per year — the fertility: births per head, each head weighted by its age group's
  `birth_weights` in `populations.tsv`.
- 1 value — the inequality: how unevenly the population's people hold their means, as the
  standard deviation of the log of their wealth. Zero holds all alike.
- 1 value — the labor spread: how unevenly its wages reach its people, in the same measure,
  standing in for skill (`FINANCIAL_MODEL.md`, "The residents and inequality").
- 1 value — the ownership spread: how unevenly its dividends reach its people, in the same
  measure.
- 1 value, with an inline `$` — the wealth per head. Its classes hold it as unevenly as its
  inequality has it, and spend it at the type's `spending_rate` (`populations.tsv`).
- 1 value — the participation: the most of its able hours the population offers, its
  weighted heads times `work_hours` (`populations.tsv`) being all of them. From the first
  interval it moves toward what its type's participation response implies.

The rates carry an inline `/y`, and the wealth an inline `$`. A cell must be present for every population that
`facilities.tsv` seeds, and is empty otherwise.


## Notes

1. The table is generated, not hand-edited: `tests/calibration/seed_demography.py` derives
   it from UN World Population Prospects 2024 for 2015, reading the type's age groups and birth
   weights from `populations.tsv`, so it follows them when they change. An inequality is a
   lognormal's with the polity's survey Gini, a polity of many countries its countries' combined
   by the Theil index with their consumption per head (`EARTH_CALIBRATION.md`, "Population"). The
   spreads hold each population nearest its inequality over what its residents were paid in the
   game's first decade, measured once, ownership's Gini a multiple of labor's from recall
   (`SPREADS`; `EARTH_CALIBRATION.md`, "Population"). A wealth is a year of what the polity's
   residents drew per head in their first interval at start prices, measured once. The
   participation is written by `tests/calibration/seed_labor.py`, from 2015 employment and
   hours from recall, and `seed_demography.py` keeps it.
2. An agency has no residents: its headcount is staff on loan from its polity (`facilities.tsv`, `staff`).
3. The shares need not sum exactly to one; the game starts each age group at its share of the
   facility's population, rounded down, and gives the remainder to the largest age group.
