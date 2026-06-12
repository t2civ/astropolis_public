# Line Items (Schema)

Line items (leaves) of the chart of accounts. Each row is one account; values accumulate per facility
and aggregate facility → player. Subtotals (revenue, cost-of-goods, gross-output, gross-profit) are
derived from these leaves in code (hard-coded `SUBTOTAL_*` constants in the financials components), not
stored as rows. See `FINANCIAL_MODEL.md` for the model.

## Fields

- name (1st column) — Item name, prefixed `FINANCIAL_ITEM_`. Line items are referenced by
  `operations.tsv` (`revenue_type` / `cogs_type`, per operation) and `facility_classes.tsv`
  (`revenue_type` / `cogs_type`, per unitary facility); the line item itself is unaware of operations or
  facility classes, and either source may produce the same item.
- statement — `Enums.StatementTypes` member (prefix `STATEMENT_`): `INCOME`, `CASH_FLOW`, or `BALANCE`.
  Drives quarter behavior: income and cash-flow leaves are flows (reset at quarter rollover); balance
  leaves are stocks (run).
- is_revenue — TRUE if this leaf sums into the `REVENUE` subtotal; FALSE sums into `COST_OF_GOODS`. (Only
  income-statement leaves carry a base subtotal in v1.)
- is_gross_output — TRUE if this (producer) revenue counts toward the `GROSS_OUTPUT` economic measure;
  FALSE for resale/transfer/tax lines (none in v1).
