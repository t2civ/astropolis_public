# Schema for storage_classes.tsv

Storage classes are described in `storage_classes.descriptive.md`.


## Fields

- name (1st column) — Storage class name per data table instructions. Represents the physical infrastructure category required to store and transport a resource.
- give — How far past its capacity a class can be filled, as a share of that capacity: the overfill at which the rent for holding stock there reaches the whole value of what it holds, per interval. Past capacity the rent rises as the square of the overfill over the give, so a class with a large give (bulk goods piled anywhere) charges little far past capacity, and one with almost none (electricity) acts as a wall. Zero means nothing past capacity can be held at any rent.


## Notes

1. Storage classes are referenced by the `storage_class` field in `resources.tsv`.
2. Unlike `trade_class` (which governs trading economics and transport cost), `storage_class` describes the physical containment and handling infrastructure. The two often coincide but diverge for resources like nuclear fuels (trade_class=BULK, storage_class=RADIOACTIVE) and high-value items (trade_class=PRECIOUS, storage_class=SPECIAL_HANDLING).
3. `PURE_FLOW` is a class no module stores: what is made of its members over an interval is what is drawn over it, since the stock levels of a class that holds nothing are nothing. It holds what cannot be kept, the services households draw and the habitation housing makes. The other service resources and compute have no storage class, keep what stock they have, and are made only as far as something draws them (`PRODUCTION_MODEL.md`, "Placeholders").
4. Capacity is soft. Up to it holding is free; past it each class charges its rent, a share of the value of what it holds, and a facility disposes of the surplus worth less than that rent: a resource with a `disposal_sink` (`resources.tsv`) is vented to it, or written off as its `waste_form`. A resource with neither (electricity, nuclear fuels and wastes) can't be disposed of, so the rent enters the margin of whatever makes it beyond its use, and its makers slow as the class fills (`PRODUCTION_MODEL.md`, "A storage class: the holding rent").
5. The `give` values are first guesses, to be tuned once the holding rent passes step 2 of "Self-regulation before tuning" (`FEEDBACK_DESIGN.md`).
