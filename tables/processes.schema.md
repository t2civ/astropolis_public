# Schema for processes.tsv

A process is a change to a locus's strata that no module makes, run in the locus's interval (`PRODUCTION_MODEL.md`, "Strata and processes"). Each acts on every stratum of its group that holds its resource. Today every process is a living stock regrowing toward its carrying capacity: logistically, fastest at half of it, solved over each interval so that it never overshoots.

## Fields

- name (1st column) — Process name per data table instructions.
- stratum_group — The stratum group it acts on. See `stratum_groups.tsv`.
- resource — The stratum resource that regrows. Must be `extraction` (`resources.tsv`). Where a polity owns the stratum (`polity` in `strata.tsv`), its owner sells what the stock may give through its facility's market, so the resource needs a `storage_class`, `PURE_FLOW` where none is kept once cut, and a `start_price`; a stock nobody owns, as the ocean's fish, is open to whoever extracts it.
- growth_rate — The stock's intrinsic growth rate, per year: how fast it grows while small against its carrying capacity.
- seeded_share — The share of its carrying capacity a stratum's seeded mass of the resource stands at (0 < value ≤ 1). A stratum's carrying capacity is its seeded mass over this share.
- free_capacity — The capacity (`capacities.tsv`) whose free amount the carrying capacity follows, or blank for none: forest grows on the land that farms and cities leave free. Where the stratum has that capacity, its carrying capacity at game start is set per unit of it left free, and follows what is left free from then on.
