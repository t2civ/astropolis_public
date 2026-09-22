# Storage Classes (Descriptive)

Storage classes categorize the physical infrastructure required to store and transport resources, whether in facility inventory, warehousing, or transport vessel holds.

- **Electricity** — Power storage infrastructure including battery banks, capacitor arrays, flywheels, gravity reservoirs, and other energy storage systems.
- **Bulk** — General-purpose warehouses, bins, silos, open storage yards, and standard freight containers for solid materials that do not require special environmental controls. The default storage class for ores, structural materials, and most basic manufactured goods.
- **Ice/Volatile** — Sealed, insulated containment for substances that sublimate or evaporate readily in the local environment. On Earth this means refrigerated or pressurized tanks; in space it means insulated bins or ice blocks in shaded storage.
- **Liquid** — Standard tanks, drums, bladders, and pipelines for liquids stored at or near ambient temperature and moderate pressure. Includes both inert and hazardous liquid containment.
- **Cryogenic** — Insulated, pressurized vessels designed to maintain liquefied gases at cryogenic temperatures. Includes dewars, cryotanks, and associated boil-off management systems.
- **Radioactive** — Heavily shielded containment for highly radioactive materials such as spent nuclear fuel and high-level radioactive waste. Includes spent fuel pools, dry cask storage, and hot cells with remote handling systems.
- **Special Handling** — Controlled-environment storage for resources that require temperature regulation, vibration isolation, electrostatic discharge protection, cleanroom conditions, security vaults, or other specialized handling not covered by other storage classes. A catchall for high-value, fragile, perishable, hazardous, or precision items.
- **Pure Flow** — No storage at all, for what cannot be kept: a service is used as it is made, and a place to live is occupied or not. No module holds this class, so what its producers make over an interval is what the facility draws over it.

Notes:

1. Capacities are deliberately generous, electricity's far beyond real grids, which hold about an hour of their generation (R18 in the development repository's `EARTH_CALIBRATION.md`). Facility processing is built to work at any storage size, but a probe at real scale found defects to fix first, and each nation's real storage will come from storage modules, so capacities stay generous until then. When setting module capacities, provide storage capacity to cover at least ~2 weeks of facility activity.
2. Even after minimum consideration above, capacities should be generous: bulk capacity is provided by almost any unused space; ice/volatiles capacity is cheap and must allow for large quantities of water; etc. 
3. Radioactive capacity comes with the reactors, 5 t per MW of reactor, so that spent fuel can accumulate for more than a century at the seeded fleets. It is a placeholder until real on-site capacity, pools and dry casks, is researched (R17 in the development repository's `EARTH_CALIBRATION.md`) and storage modules can add capacity where it runs short.
