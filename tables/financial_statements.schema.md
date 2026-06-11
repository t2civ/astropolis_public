# Financial Statements (Schema)

Enumeration of the three accounting statements. A `financial_items.tsv` row's `statement` selects one.
`INCOME` and `CASH_FLOW` are period flows (reset at quarter rollover); `BALANCE` is a running stock.
Drives the Budget GUI subtabs. See `FINANCIAL_MODEL.md` for the model.

## Fields

- name (1st column) — Statement name, prefixed `FINANCIAL_STATEMENT_`. Rows: `INCOME`, `CASH_FLOW`,
  `BALANCE`.
