# Financial Items (Schema)

Line items (leaves) of the chart of accounts. Each row is one account; values accumulate per facility
and aggregate facility → player. Subtotals are derived from these leaves, not stored as rows here (see
`financial_subtotals.tsv`). See `FINANCIAL_MODEL.md` for the model.

## Fields

- name (1st column) — Item name, prefixed `FINANCIAL_ITEM_`. v1 convention: `<OP_CLASS>_REVENUE` /
  `<OP_CLASS>_COGS` for the per-activity income lines, keyed off `op_classes.tsv`.
- statement — `financial_statements.tsv` row. Drives quarter behavior: `INCOME` and `CASH_FLOW` are flows
  (reset at quarter rollover); `BALANCE` is a stock (runs).
- subtotal_group — `financial_subtotals.tsv` base subtotal this item sums into (`REVENUE` or
  `COST_OF_GOODS`).
- is_gross_output — TRUE if this (producer) revenue counts toward the `GROSS_OUTPUT` economic measure;
  FALSE for resale/transfer/tax lines (none in v1).
