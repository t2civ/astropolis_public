# Schema for globals.tsv

Game-wide scalar values that are not properties of any entity. The table is
`@DB_ANONYMOUS` and holds exactly one row, so there is no entity name; code reads it as
row 0.

Values here are game-start seeds at the 2015 vintage, like every other seed in
`public/tables/`, except `haul`, which holds through the game.


## Table Data

- biodiversity_pool — FLOAT in `spp` (effective species). The pool of macroscopic
  species the whole game draws on, from which each facility's `biodiversity_fraction`
  in `facilities.tsv` samples. It is global rather than per-locus on purpose: a habitat
  on Mars houses Earth species, so there is one pool and off-world biomes sample the
  same one. See the Information & Biodiversity section of `facilities.schema.md` for
  how sampling and shared content work.
- information_pool — FLOAT in `bit`. The equivalent pool for Shannon information, from
  which `information_fraction` samples.
- haul — FLOAT, a share. The length of every locus's haul as a share of its body's mean
  radius, one share for every locus: what a unit moved from a stock to its user draws of
  its carrier's service (`storage_classes.tsv`, carrier). 0 moves everything for nothing.


## Notes

1. A pool is not a normalization constant and cannot be replaced by absolute per-facility
   values. Each facility draws a random subset of a shared set of keys sized by the log
   of the pool, and the overlap between two facilities' subsets is their shared content.
   That is why the fractions in `facilities.tsv` sum to more than 1, and why a facility
   cannot hold more diversity or information than the pool.
