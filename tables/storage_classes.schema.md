# Schema for storage_classes.tsv

Storage classes are described in `storage_classes.descriptive.md`.


## Fields

- name (1st column) — Storage class name per data table instructions. Represents the physical infrastructure category required to store and transport a resource.


## Notes

1. Storage classes are referenced by the `storage_class` field in `resources.tsv`.
2. Unlike `trade_class` (which governs trading economics and transport cost), `storage_class` describes the physical containment and handling infrastructure. The two often coincide but diverge for resources like nuclear fuels (trade_class=BULK, storage_class=RADIOACTIVE) and high-value items (trade_class=PRECIOUS, storage_class=SPECIAL_HANDLING).
3. `PURE_FLOW` is a class no module stores: what is made of its members over an interval is what is drawn over it, and the rest of their producers' capacity is curtailed. It holds what cannot be kept, the services households draw and the habitation housing makes. The other service resources and compute have no storage class and keep unbounded stock until they have consumers (`PRODUCTION_MODEL.md`, "Placeholders").
4. A facility's operations fill a storage class no further than a ceiling below its disposal level: past it, the least valuable members' producers are curtailed, and a co-product an operation makes while running for another output is vented to its `disposal_sink` (`resources.tsv`), or written off as its `waste_form` where no stratum can hold it. A class whose members have neither (ELECTRICITY, RADIOACTIVE) fills to its capacity and is never vented. A class filled past its disposal level by deliveries, salvage or residents disposes of its least valuable surplus the same way, keeping each resource's operations and strategic reserves and a minimum share of the class.
