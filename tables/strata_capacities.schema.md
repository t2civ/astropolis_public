# Schema for strata_capacities.tsv

This Entity x Entity table gives the capacities each stratum has at game start (`capacities.tsv`). They are game-start values: read once in a new game and kept as the stratum's state from then on, which technology and development may change.

## Table Data

The data type is FLOAT, with its unit inline: an area for land (e.g., `8.6e6 km^2`), the power of the plant the sites take for a power capacity (e.g., `3e4 MW`). A module's `occupancy` (`modules.tsv`) must be given in a unit of the same kind.

An empty cell means the stratum has no limit of that capacity: modules occupying it run and are built as if every site were the best. Zero means the stratum has none of it.

## Notes

1. A facility's modules occupy the capacity of the stratum it stands on that has it (`region` in `facilities.tsv`). A facility may stand on only one stratum with each capacity.
2. Land is the land fit for farms and building, not all of a region's area. What its farms and cities leave free is forest and wild land, and the carrying capacity of a process that follows it (`processes.tsv`, `free_capacity`) follows the share left free.
3. Hydro, geothermal and tidal are the potential of a region's sites, the best developed first. Tidal sites lie on a region's continental shelf, the rest on its surface. Wind is sized for what the region's grid takes of it without storage: at its capacity it would make about 40% of the electricity the grid used at game start.
