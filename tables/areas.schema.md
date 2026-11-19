# Schema for areas.tsv and domains.tsv

The two groupings of `technologies.tsv`. Each technology names its research area, and each area names its knowledge domain. They organize what a player sees and how research is allocated, never what a technology does or how technologies bear on one another (the development repository's `TECHNOLOGY_MODEL.md`, "Domains and areas"). Each is described in `technologies.descriptive.md`.


## areas.tsv

- name (1st column) — Area name per data table instructions, `AREA_` prefix.
- domain — TABLE_ROW `domains.tsv`, the knowledge domain the area belongs to.

Areas are listed in display order within their domains.


## domains.tsv

An enumeration, `DOMAIN_` prefix, in display order.
