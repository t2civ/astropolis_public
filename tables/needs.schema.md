# Schema for needs.tsv

Each row is a need: something every member of a population type wants filled, such as
sustenance, room, health or learning. A need is a tier, a name and its reach past its want.
What fills it, and how much of it each type wants, is `wants.tsv`, and the code never names a
need (`POPULATION_MODEL.md`, "A population is what it needs" and "Needs").


## Table Data

- tier — `Enums.NeedTiers`: what going without the need does, and how fast.
  - `EXISTENCE` — Without it an individual stops. The residents buy it first, with all they
    spend if it takes that, and its satisfaction is smoothed over about a month; below its
    type's `starvation_threshold` (`populations.tsv`) people starve.
  - `WELLBEING` — Going without is chronic. It is bought from what existence leaves, by
    `spending_share` (`wants.tsv`).
  - `FULFILLMENT` — What sentient beings require beyond the other two. It is bought as
    wellbeing is.
- satiation_headroom — FLOAT, the need's reach: the most a want for it satisfies past the
  want, approached with diminishing returns as a decile buys past it, past a fill f of one a
  satisfaction of 1 + h(1 − e^(−(f − 1)/h)) (`FINANCIAL_MODEL.md`, "Saving and borrowing").
  Default `0.1`, where more past the want buys little more life or learning. Room's is long,
  since a home with room to spare is what a family forms in, and its plenty raises births
  (`POPULATION_MODEL.md`, "Demographics", the responses' shape).


## Notes

1. A need's satisfaction for a type is the share of the type's want for it that the
   residents got. Where a type fills a need with more than one want, each counts by its
   value at the facility's long prices, its local prices averaged over a decade, or by head
   count where none is worth anything.
