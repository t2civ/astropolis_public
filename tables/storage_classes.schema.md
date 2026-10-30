# Schema for storage_classes.tsv

Storage classes are described in `storage_classes.descriptive.md`.


## Fields

- name (1st column) — Storage class name per data table instructions. Represents the physical infrastructure category required to store and transport a resource.
- overflow — How far past its capacity a class can be filled, as a share of that capacity, or of what it holds where that is more. Past capacity a class's space is improvised, at no less than what a new store's space would cost where one can be built, and at more as the overfill grows: by its full overflow, by what the class holds is worth over an interval, or that store's cost again, whichever is more. So a class with a large give (bulk goods piled anywhere) improvises cheaply far past capacity, and one with almost none (electricity) acts nearly as a wall; and a class holding what it can't vent past little or no capacity of its own, as a station may, improvises at a price bounded by what it holds is worth. Zero means nothing past capacity can be improvised.
- space — The resource that is this class's space: a unit of the class's capacity held through time, a pure flow priced at each facility. Blank: the class has no space of its own, and keeps nothing past its members' levels (`PURE_FLOW`).


## Notes

1. Storage classes are referenced by the `storage_class` field in `resources.tsv`.
2. Unlike `trade_class` (which governs trading economics and transport cost), `storage_class` describes the physical containment and handling infrastructure. The two often coincide but diverge for resources like nuclear fuels (trade_class=BULK, storage_class=RADIOACTIVE) and high-value items (trade_class=PRECIOUS, storage_class=SPECIAL_HANDLING).
3. `PURE_FLOW` is a class no module stores, with no overflow and no space: what is made of its members over an interval is what is drawn over it, since the stock levels of a class that holds nothing are nothing. No code treats it apart: it behaves as the limit of a class with little storage. It holds what cannot be kept: the services, compute, habitation and labor, and the classes' space itself.
4. A class's space is priced at each facility (`PRODUCTION_MODEL.md`, "What a facility is", storage rent): a store's operation makes space for a running cost, and what the class holds draws it; no module carries storage of its own (`modules.schema.md`, note 4). A level is held as far as its space pays for it, a surplus that can be vented is disposed of where its keep would cost more than it is worth, and a maker of what can't be vented, nuclear fuels and wastes, pays for the keep of what it makes. A space resource's `trade_unit` is the class's unit held for a year, its `start_price` only a seed: within a store space costs what running it takes.
5. The `overflow` values are first guesses, to be tuned once storage rent passes step 2 of "Self-regulation before tuning" (`FEEDBACK_DESIGN.md`).
