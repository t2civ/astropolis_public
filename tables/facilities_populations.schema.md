# Schema for facilities_populations.tsv

This Entity x Entity table defines the age structure, vital rates, inequality and its spreads,
wealth, schooling and participation of each population at facilities at simulation start in 2015.
How many a facility holds of each type is `population` in `facilities.tsv`; this table says how
they are spread over the type's eight age groups, how fast they die and bear children, how
unevenly they hold their means and are paid, what they hold and save, the schooling they hold and
how much they work. It is the populations' starting state: from the first interval their death
rates, fertility and participation move with what they get, their schooling with the learning
their young get and as they age, and their inequality with how unevenly what they are paid
reaches them (`populations.schema.md`). Population types are described in
`populations.schema.md`, and the model in `POPULATION_MODEL.md` ("Demographics").


## Table Data

The data type is ARRAY[FLOAT]; each cell holds 32 values delimited by semicolons:

- 8 values — each age group's share of the population, in the order of the type's age groups.
- 8 values, per year — the deaths per head in each age group.
- 1 value, per year — the fertility: births per head, each head weighted by its age group's
  `birth_weights` in `populations.tsv`.
- 1 value — the inequality: how unevenly the population's people hold their means, as the
  standard deviation of the log of their wealth. Zero holds all alike.
- 1 value — the labor spread: what its people's schooling doesn't explain of what an hour of
  theirs makes, spread over its deciles as their means are, in the same measure
  (`POPULATION_MODEL.md`, "Productivity and schooling").
- 1 value — the ownership spread: how unevenly its dividends reach its people, in the same
  measure.
- 1 value, with an inline `$` — the wealth per head. Its deciles hold it as unevenly as its
  inequality has it, and spend it at the type's `spending_rate` (`populations.tsv`).
- 1 value — the saving rate: the share of what its residents are paid, wages, transfers and
  dividends, that they save and offer the credit market, kept as the population's own
  (`FINANCIAL_MODEL.md`, "Saving and borrowing").
- 8 values, with an inline `y` — the years of schooling each age group holds on average. An age
  group that gains schooling holds what its people will carry out of it (`schooling_rates` in
  `populations.tsv`).
- 1 value, with an inline `y` — the schooling spread: how widely each age group's schooling is
  spread over its deciles, the most to the best off, as the standard deviation of its people's
  years: each decile stands at the mean plus the spread times its place in a normal distribution,
  none below nothing and the mean kept.
- 1 value — the participation: the most of its able hours the population offers, its
  weighted heads times `work_hours` (`populations.tsv`) being all of them. From the first
  interval it moves toward what its type's participation response implies.

The rates carry an inline `/y`, the wealth an inline `$` and the schooling an inline `y`. A cell
must be present for every population that `facilities.tsv` seeds, and is empty otherwise.


## Notes

1. The table is generated, not hand-edited: `tests/calibration/seed_demography.py` derives
   it from UN World Population Prospects 2024 for 2015, reading the type's age groups and birth
   weights from `populations.tsv`, so it follows them when they change. An inequality is a
   lognormal's with the polity's survey Gini, a polity of many countries its countries' combined
   by the Theil index with their consumption per head (`EARTH_CALIBRATION.md`, "Population"). The
   labor spread holds each population nearest its inequality over the game's first five years,
   read from games at several spreads, and the ownership spread's Gini is a multiple of what the
   wages' was seeded at before, from recall (`SPREADS`; `EARTH_CALIBRATION.md`, "Population").
   A wealth is, at the USA, the one at which its residents' deciles buy their wants whole a year
   at start prices, public provision buying its share (`--wealth`); at every other polity, the
   USA's times what its households spent a head in 2015 against the USA's at market rates, from
   recall (`HOUSEHOLD_SPENDINGS`), since start prices price a poorer polity's in-person services at
   the USA's wage. A saving rate
   is what the polity's households saved in 2015, from recall (`SAVING_RATES`). The schooling is
   the polity's attainment by age in 2015, and its spread from the shares holding each level of
   school, from recall (`SCHOOLINGS`, `SCHOOLING_SPREADS`), which `seed_demography.py --schooling`
   rewrites alone from the table's own shares; what an hour
   worked made there past what its schooling gives is its technology's (`players_domains.tsv`). The participation is written by `tests/calibration/seed_labor.py`, from 2015
   employment and hours from recall, and `seed_demography.py` keeps it.
2. An agency has no residents: its headcount is staff on loan from its polity (`facilities.tsv`, `staff`).
3. The shares need not sum exactly to one; the game starts each age group at its share of the
   facility's population, rounded down, and gives the remainder to the largest age group.
