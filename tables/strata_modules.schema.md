# Schema for strata_modules.tsv

This Entity x Entity table says which modules can work each stratum, and how the stratum's geology bears on them (`PRODUCTION_MODEL.md`, "Strata and processes", extraction). Only a module that works the stratum's zone (`zone` in modules.tsv and stratum_groups.tsv) reads its cell. Strata are described in `strata.descriptive.md`, modules in `modules.descriptive.md`.


## Table Data

The data type is FLOAT: the stratum's yield for the module, a factor on what its operations extract for what drives them. 1 leaves each operation's own values.

An empty cell means the module can't work the stratum: a facility standing on it can't have the module's operations.


## Notes

1. The factors are geology only: how deep and hard a stratum's deposits lie. What a unit takes in labor, administration and upkeep is its population's and its technology's, never a stratum's.
2. Not yet read: the yield. A module whose cell is filled runs at its operations' own values.
