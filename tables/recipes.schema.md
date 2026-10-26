# Schema for recipes.tsv

Each row is a shared recipe: a bundle of resources that many operations or modules draw in the same
mix. An operation names one for its administration and one for its maintenance, and a module one
for its upkeep, each with a size (`operations.schema.md`, `modules.schema.md`), and what a sharer
draws of each resource is the recipe's rate times its size. The facility sums what a recipe's
sharers draw before the clear, which takes each resource on its own, and values a recipe once for
all who share it (`PRODUCTION_MODEL.md` in the development repository, "What a facility is", shared
recipes).

## Fields

- in_inventory — The resources the recipe draws.
- in_inventory_rates — What it draws of each per unit of a sharer's size, parallel to
  `in_inventory`. The column's unit, kg/h, applies per element, so a service's rate carries its own
  (`h/h`), as in `operations.tsv`.
