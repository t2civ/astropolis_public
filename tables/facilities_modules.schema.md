# Schema for facilities_modules.tsv

This Entity x Entity table defines module quantities and configurations at facilities at simulation start in 2015. Facilities are described in `facilities.descriptive.md`. Modules are described in `modules.descriptive.md`.


## Table Data

The data type is ARRAY[FLOAT]; each cell contains float values delimited by semicolons. Values are the current installed and configured capacity for each supported operation specified by `operations` in `modules.schema.md`. The cell should be empty if all capacities are 0. Otherwise, number of float values must correspond to number of supported operations in `modules.schema.md`.


## Notes

1. Capacity is what an operation makes at its full run. An operation whose margin sets its run runs at its whole capacity wherever it pays, so its capacity is what it makes, not its nameplate: Earth's plant ran at two thirds to nine tenths of its capacity, and its fossil power plants at a tenth to three quarters, idle for demand's daily and seasonal swings, the business cycle and outages, which the sim's steady demand doesn't have (`facilities_operations.schema.md` note 1). Renewable power's capacity is its nameplate, which its environment's capacity factor runs; for solar power, use peak capacity assuming direct sunlight in space at 1 AU (this will be more consistent with off-Earth usage).
2. The unit of capacity follows from the operation's normalization in `operations.tsv`. For Energy group modules, one unit of capacity corresponds to 1 MW of electricity output. For other modules, see `operations.schema.md` for the applicable normalization.
3. An empty cell means the module is not present at the facility (zero capacity for all of its operations).
4. At the Earth polities, the capacities of the services firms buy (ACCOUNTING_SERVICES, BUSINESS_SERVICES, CONSULTING, MARKETING_ADVERTISING, LEGAL_SERVICES, INSURANCE_RISK, CYBERSECURITY) are written by `tests/calibration/seed_services.py`: what the polity's operations draw of each at their seeded runs, or for administration on their capacities in service, at the maker's seeded run, and for legal services and insurance besides what they held for the residents. Their ENGINEERING_DESIGN is seeded to what the polity's builds draw at the start, each module at its `design_rate` (`modules.schema.md`).
5. At the Earth polities, the power plants' capacities are written by `tests/calibration/seed_power.py`, each power operation's at the polity's 2015 generation from it at its seeded utilization, a peaker's carrying besides the shade its polity's solar leaves it, and Earth's plant that loses at the start's prices, its oil plants among them, seeded as the gas plant on its module; the coal mines' by `tests/calibration/seed_coal.py`, the world's what its plant burns at its seeded runs, shared and split by depth as 2015's output was; and the makers of the start's fuels and intermediate goods, the wells, mines and plants of its energy, steel and chemicals, by `tests/calibration/seed_chains.py`, the world's what the seeded runs, upkeep, residents and buildouts draw of each, every polity keeping its share of the making.
