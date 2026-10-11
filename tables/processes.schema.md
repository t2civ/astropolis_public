# Schema for processes.tsv

A process is a change to a body's strata that no module makes, run in the body's interval (`PRODUCTION_MODEL.md`, "Strata and processes"). Each acts on every stratum of its group that holds its resource. Today every process is a living stock regrowing toward its carrying capacity: logistically, fastest at half of it, solved over each interval so that it never overshoots.

## Fields

- name (1st column) — Process name per data table instructions.
- stratum_group — The stratum group it acts on. See `stratum_groups.tsv`.
- resource — The stratum resource that regrows. Must be `is_extraction` (`resources.tsv`).
- growth_rate — The stock's intrinsic growth rate, per year: how fast it grows while small against its carrying capacity.
- seeded_share — The share of its carrying capacity a stratum's seeded mass of the resource stands at (0 < value ≤ 1). A stratum's carrying capacity is its seeded mass over this share.
