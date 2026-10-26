# Schema for recipes.tsv

Each row is a shared recipe: a bundle of resources that many operations or modules draw in the same
mix. An operation names one for its administration and one for its maintenance, and a module one
for its upkeep, each with a size (`operations.schema.md`, `modules.schema.md`), and what a sharer
draws of each resource is the recipe's rate times its size. The facility sums what a recipe's
sharers draw before the clear, which takes each resource on its own, and values a recipe once for
all who share it (`PRODUCTION_MODEL.md` in the development repository, "What a facility is", shared
recipes).

The recipes are written by `tests/calibration/seed_services.py`, each with its first member at 1, so
a sharer's size is what it draws of that member:
- `ADMIN_*` — what an organization of a kind keeps itself with, its members its shares of the
  buyer's gross output: industry, utilities, farms, the makers that sell to households, the local
  services, government, media, the professional offices and finance.
- `MAINTENANCE_*` — the parts a kind of plant wears, and the field engineering that inspects and
  overhauls it; `MAINTENANCE_COMPUTE`, the cybersecurity that keeps compute running.
- `UPKEEP_*` — what a kind of structure needs for being there.

## Fields

- in_inventory — The resources the recipe draws.
- in_inventory_rates — What it draws of each per unit of a sharer's size, parallel to
  `in_inventory`. The column's unit, kg/h, applies per element, so a service's rate carries its own
  (`h/h`), as in `operations.tsv`.
