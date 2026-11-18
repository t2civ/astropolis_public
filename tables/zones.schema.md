# Schema for zones.tsv

A zone is where in a body a module works: its atmosphere, a depth below its solid surface, an ocean. It is all an operation knows of the stratum it draws on, so an extraction is named for its intent and its zone, never for a stratum (`PRODUCTION_MODEL.md`, "Strata and processes", extraction). Each stratum group lies in one zone or none (`zone` in stratum_groups.tsv), and a facility stands on at most one stratum of each zone.


## Fields

- name (1st column) — Zone name per data table instructions, generic to every body: e.g., `SURFACE`, `DEEP_SUBSURFACE`.
- alt_of — The zone this one is another area of, or blank for a primary zone (see Alt Zones).
- atmosphere — The facility's stratum of this zone is its atmosphere, which an operation's `in_atmos` and `out_atmos` flows draw from and add to. At most one zone.
- surface — The facility's stratum of this zone is its surface, which an operation's `out_surface` flows add to. At most one zone.


## Depths

The zones below a solid surface are depth tiers, Earth's continental strata giving their bounds: `SURFACE` to 0.1 km, `NEAR_SURFACE` to 0.5 km, `SUBSURFACE` to 2 km, `DEEP_SUBSURFACE` to 5 km, `EXTREME_SUBSURFACE` to 11 km. An operation's depth is part of its intent: what a unit run of it extracts and draws is set for its tier, and how far a stratum's depth or hardness departs from its tier's is the stratum's yield (`strata_modules.tsv`). Mining here means extraction as it is done on Earth, by mines and wells; past 11 km none reaches, and what lies deeper will be taken by operations of its own, whole-body harvest, not by mining.


## Alt Zones

Some zones hold strata side by side, each over its own area: a nation's continental surface and its shelf, the Moon's regolith and its polar shaded regolith, its terrae crust and its maria. A facility may stand on all of them, as the one facility a player has on the Moon does, so each area past the first is a zone of its own, an alt of its primary (`SURFACE_ALT`, `SURFACE_ALT2`, `SUBSURFACE_ALT`), and a facility still stands on at most one stratum of each zone. Which area is the primary is a convention, the larger.

An alt zone is worked by alt modules and operations (`alt_of` in modules.tsv and operations.tsv): each a copy of its primary row but for its name, the zone or module that places it, and a module's own operations, its primary's alts in order. So an intent's values stay one, as its yield on each stratum (`strata_modules.tsv`) and its seeds stay each its own. The server asserts at startup that every alt row still copies its primary; `python tests/sync_alt_rows.py` copies a primary's edits to its alts. An alt zone is never a facility's atmosphere or surface.


## Mapping Stratum Groups

A stratum group's zone is the depth tier where a mine or a well first works it, from its top:

- The surface zone holds the outermost solid stratum at a place: a regolith, an icy surface, or a small body's bulk, which is worked from its surface. Strata side by side at the surface take its alts.
- A group that several bodies share takes the deepest tier any of them needs, so no body stands on two strata of one zone: `CRUST` lies under a near-surface stratum on Mercury, so it is `SUBSURFACE` everywhere, though on Ceres or Io it begins a few metres down. Where a stratum lies shallower than its tier, its yield says so.
- A stratum spanning two tiers takes the upper: Mars's subsurface (0.5 to 5 km) is `SUBSURFACE`, and its deep crust, from 5 km, `EXTREME_SUBSURFACE`, as is Venus's.
- A group that begins past 11 km lies in no zone.

| Zone | Stratum groups (bodies) |
|---|---|
| `ATMOSPHERE` | `ATMOSPHERE` (Earth, Venus, Mars, Jupiter, Saturn, Titan) |
| `SURFACE` | `CONT_SURFACE`, `ANTARCTIC_CONT_SURFACE` (Earth); `REGOLITH` (Mercury, the Moon, Mars, Ceres, Vesta, Pallas); `SURFACE` (Venus, Io, Callisto, Titan, Tethys, Dione, Rhea, Iapetus); `ICE_SURFACE` (Europa, Ganymede, Mimas, Enceladus); `BULK` (Phobos, Deimos, Amalthea, Hyperion, Phoebe) |
| `SURFACE_ALT` | `CONT_SHELF`, `ANTARCTIC_CONT_SHELF` (Earth); `POLAR_SHADED_REGOLITH` (Mercury, the Moon); `NORTH_POLAR_CAP` (Mars) |
| `SURFACE_ALT2` | `OCEAN_FLOOR` (Earth); `SOUTH_POLAR_CAP` (Mars) |
| `NEAR_SURFACE` | `CONT_NEAR_SURFACE`, `ANTARCTIC_CONT_NEAR_SURFACE` (Earth); `NEAR_SURFACE` (Mercury, Venus, the Moon, Mars) |
| `SUBSURFACE` | `CONT_SUBSURFACE`, `ANTARCTIC_CONT_SUBSURFACE` (Earth); `SUBSURFACE` (Venus, Mars); `CRUST` (Mercury, Ceres, Vesta, Io, Tethys, Iapetus); `CRUST_TERRAE` (the Moon); `CRUST_MANTLE` (Pallas); `ICE_SHELL` (Europa, Titan, Mimas, Enceladus, Dione); `OUTER_ICE_SHELL` (Ganymede); `OUTER_SHELL` (Callisto, Rhea) |
| `SUBSURFACE_ALT` | `CRUST_MARIA` (the Moon) |
| `DEEP_SUBSURFACE` | `CONT_DEEP_SUBSURFACE`, `ANTARCTIC_CONT_DEEP_SUBSURFACE` (Earth) |
| `EXTREME_SUBSURFACE` | `CONT_EXTREME_SUBSURFACE`, `ANTARCTIC_CONT_EXTREME_SUBSURFACE` (Earth); `DEEP_CRUST` (Venus, Mars) |
| `OCEAN` | `OCEAN` (Earth); `HYDROCARBON_BODIES` (Titan) |
| none | `CONT_ICE_BODIES`, `ANTARCTIC_CONT_ICE_BODIES`, the `ULTRA_SUBSURFACE` and `LOWER_CRUST` groups and `OCEAN_CRUST` (Earth); `MANTLE`, `CORE`, `INTERIOR`, `MOL_H_ENVELOPE`, `MET_H_ENVELOPE`, `INNER_ICE`, `SUBSURFACE_OCEAN` |


## Notes

1. A module works one zone (`zone` in modules.tsv), and where a stratum of that zone can be worked by it is in `strata_modules.tsv`. Earth's and the Moon's strata allow modules today, with Mercury's regolith, Mars's atmosphere and regolith, and Titan's atmosphere and seas; every other zone above changes nothing until a stratum in it allows one.
2. `OCEAN` holds any body of liquid at a surface: Earth's ocean and Titan's hydrocarbon seas.
3. Operations the mapping makes room for, none built yet: mining off Earth by the present intents, alts where a body's areas lie side by side (Mars's polar caps, a third surface); surface ice extraction for icy surfaces and polar caps; mines at extreme depth, for Mars's and Venus's deep crusts; deep-sea mining on Earth's ocean floor; shelf mining; bulk processing of small bodies, an intent of its own working their `SURFACE`; and whole-body harvest, past the zones.
