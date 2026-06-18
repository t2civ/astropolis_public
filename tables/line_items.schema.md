# Line Items (Schema)

Line items (leaves) of the chart of accounts. Each row is one account; values accumulate per facility
and aggregate facility → player. Subtotals (revenue, cost-of-goods, gross-output, gross-profit,
operating-expense, operating-income, net-cash-flow, and the balance-sheet assets, liabilities, equity)
are derived from these leaves in code
(hard-coded `SUBTOTAL_*` constants in the financials components), not stored as rows. See
`FINANCIAL_MODEL.md` for the model.

## Fields

- name (1st column) — Item name, prefixed `LINE_ITEM_`. Line items are referenced by
  `operations.tsv` (`revenue_type` / `cogs_type`, per operation) and `facility_classes.tsv`
  (`revenue_type` / `cogs_type`, per unitary facility); the line item itself is unaware of operations or
  facility classes, and either source may produce the same item.
- unique_type — `Enums.UniqueLineItems` member (no prefix). Tags a row booked directly from engine
  code, which resolves it via `db_find` on this column instead of by hard-coded row name. Blank for
  content rows referenced by `operations.tsv` / `facility_classes.tsv`. Each enum value appears on
  exactly one row.
- statement — `Enums.StatementTypes` member (prefix `STATEMENT_`): `INCOME`, `CASH_FLOW`, or `BALANCE`.
  Drives quarter behavior (income and cash-flow leaves are flows, reset at quarter rollover; balance
  leaves are stocks, run) and subtotal routing (below).
- revenue — for an `INCOME` leaf, TRUE sums into the `REVENUE` subtotal, FALSE into `COST_OF_GOODS`
  (unless `operating_expense`, below).
  For a `CASH_FLOW` leaf, TRUE is an inflow (+) and FALSE an outflow (−) in the signed
  `NET_CASH_FLOW` subtotal. Unused for `BALANCE` leaves (stocks carry no base subtotal; read
  individually).
- gross_output — TRUE if this (producer) revenue counts toward the `GROSS_OUTPUT` economic measure;
  FALSE for resale/transfer/tax/trading lines (e.g. `TRADING_GAINS` is real revenue but not
  production).
- operating_expense — for an `INCOME` cost leaf, TRUE routes it into the `OPERATING_EXPENSE` subtotal
  (a fixed/overhead cost, below gross profit) instead of `COST_OF_GOODS`; operating income is the derived
  `gross profit − operating expense`. Unused for revenue, cash-flow, and balance leaves.
- balance_class — for a `BALANCE` leaf, its `Enums.BalanceClasses` member (prefix `BALANCE_CLASS_`):
  `ASSET`, `LIABILITY`, or `EQUITY`. Routes the leaf into the assets, liabilities, or equity subtotal.
  Unused for `INCOME`/`CASH_FLOW` leaves (leave blank).
