# Financial Subtotals (Schema)

Enumeration of derived roll-ups computed from `financial_items.tsv` leaves; subtotals are not stored as
line items. `REVENUE` and `COST_OF_GOODS` are leaf sums (by each leaf's `subtotal_group`); `GROSS_OUTPUT`
sums leaves flagged `is_gross_output`; `GROSS_PROFIT` = `REVENUE` − `COST_OF_GOODS`. See
`FINANCIAL_MODEL.md` for the model.

## Fields

- name (1st column) — Subtotal name, prefixed `FINANCIAL_SUBTOTAL_`. Rows: `REVENUE`, `COST_OF_GOODS`,
  `GROSS_OUTPUT`, `GROSS_PROFIT`.
