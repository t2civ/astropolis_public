# Schema for zones.tsv

A zone is where in a body a module works: the atmosphere, a solid surface, a depth below it, an ocean. It is all an operation knows of the stratum it draws on, so an extraction is named for its intent and its zone, never for a stratum (`PRODUCTION_MODEL.md`, "Strata and processes", extraction). Each stratum group lies in one zone or none (`zone` in stratum_groups.tsv), and a facility stands on at most one stratum of each zone.


## Fields

- name (1st column) — Zone name per data table instructions, generic to every body: e.g., `SURFACE`, `DEEP_SUBSURFACE`.
- atmosphere — The facility's stratum of this zone is its atmosphere, which an operation's `in_atmos` and `out_atmos` flows draw from and add to. At most one zone.
- surface — The facility's stratum of this zone is its surface, which an operation's `out_surface` flows add to. At most one zone.


## Notes

1. A module works one zone (`zone` in modules.tsv), and where a stratum of that zone can be worked by it is in `strata_modules.tsv`.
2. `OCEAN` holds any body of liquid at a surface: Earth's ocean and Titan's hydrocarbon seas.
