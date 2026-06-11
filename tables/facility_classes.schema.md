# Facility Classes (Schema)

Classification of facilities for financial accounting. A `facilities.tsv` row's `facility_class` selects
one. For a unitary facility (one economic activity), the class supplies the line items its whole market
footprint books into; for a non-unitary facility the class is descriptive (it books per operation via
`operations.tsv`). Shares the `revenue_type` / `cogs_type` fields with `operations.tsv`. See
`FINANCIAL_MODEL.md` for the model.

## Fields

- name (1st column) — Class name, prefixed `FACILITY_CLASS_`. Current rows: `POLITY` (the nations;
  placeholder, no revenue or cost), `GROUND_FACILITIES` (Earth space agencies), `RESEARCH_STATION`
  (ISS / Tiangong slices).
- revenue_type — `financial_items.tsv` line item this class's revenue books into. Empty for none.
- cogs_type — `financial_items.tsv` line item this class's cost books into. R&D facilities use
  `RESEARCH_DEVELOPMENT` (treated as a cost of goods for now). Empty for none.
