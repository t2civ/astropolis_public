# Schema for needs.tsv

Each row is a need: something every member of a population type wants filled, such as
sustenance, room, health or learning. A need is only a tier and a name. What fills it, and
how much of it each type wants, is `wants.tsv`, and the code never names a need
(`POPULATION_MODEL.md`, "A population is what it needs" and "Needs").


## Table Data

- tier — `Enums.NeedTiers`: what going without the need does, and how fast.
  - `EXISTENCE` — Without it an individual stops. The residents buy it first, with all they
    spend if it takes that, and its satisfaction is smoothed over about a month; below its
    type's `starvation_threshold` (`populations.tsv`) people starve.
  - `WELLBEING` — Going without is chronic. It is bought from what existence leaves, by
    `spending_share` (`wants.tsv`).
  - `FULFILLMENT` — What sentient beings require beyond the other two. It is bought as
    wellbeing is.


## Notes

1. A need's satisfaction for a type is the share of the type's want for it that the
   residents got. Where a type fills a need with more than one want, each counts by its
   value at the `start_price`s in `resources.tsv`, or by head count if none has one.
