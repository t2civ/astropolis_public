# Schema for capacities.tsv

A capacity is what a stratum has that modules occupy and don't draw down: land, and the sites of geothermal, hydro, tidal and wind power (`PRODUCTION_MODEL.md`, "Strata and processes"). How much of each a stratum has is a game-start value in `strata_capacities.tsv`; what a module occupies is in `modules.tsv` (`occupies`, `occupancy`). Its sites are taken best first: a site's quality, the share of what a unit on the best site makes that a unit there makes, is `1 - x^p` at the share `x` of the capacity occupied before it, and nothing past the capacity. Units running make what the average of the sites they occupy gives; a new unit is weighed at the next site's quality.

The wind capacity is sized for what a grid takes without storage rather than for the wind a stratum gets, since wind's intermittency, weather over days, is left out. Solar has no sites: the hours of light bound it (`PRODUCTION_MODEL.md`, "Light and shade").

## Fields

- name (1st column) — Capacity name per data table instructions.
- quality_exponent — `p` above (> 0): how long the sites stay good as the capacity fills. Large for a capacity whose sites are much alike until the last of them, small for one whose sites fall off steadily from the best.
