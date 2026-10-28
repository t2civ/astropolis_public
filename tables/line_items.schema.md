# Line Items (Schema)

Line items (leaves) of the chart of accounts. Each row is one account; values accumulate per facility
and aggregate facility → player. Subtotals (revenue, cost-of-goods, gross-output, gross-profit,
operating-expense, operating-income, net-cash-flow, and the balance-sheet assets, liabilities, equity)
are derived from these leaves in code
(hard-coded `SUBTOTAL_*` constants in the financials components), not stored as rows. See
`FINANCIAL_MODEL.md` for the model.

A leaf holds one direction and never goes negative, except `TRADE_RECEIVABLES` and the cash
balances, `CASH`, `GOVERNMENT_CASH` and `CORPORATE_CASH`, which may run below nothing between an
account's settlements, where what it is short is booked as its debt (`DEBT`, `GOVERNMENT_DEBT`,
`CORPORATE_DEBT`). An event that can go either way books its size to one of a pair by its sign: `TRADING_GAINS` / `TRADING_LOSSES`, `DISPOSAL_GAINS` /
`DISPOSAL_LOSSES`, `EXCHANGE_CLEARING_GAINS` / `EXCHANGE_TAKE_COGS`, and on the cash-flow
statement `PL_SETTLEMENTS` / `PL_PAYMENTS`, `EXCHANGE_TAKE_RECEIVED` / `EXCHANGE_TAKE_PAID`,
`PAYOUTS_PAID` / `FUNDING_RECEIVED` and each treasury's side of them,
at an agency `APPROPRIATIONS_RECEIVED` / `APPROPRIATION_LAPSES_PAID` and at its polity
`APPROPRIATION_LAPSES_RECEIVED` / `APPROPRIATIONS_PAID`, `TRANSFERS_PAID` / `LEVIES_RECEIVED`,
`DIVIDENDS_PAID` / `CAPITAL_PAID_IN`, and `BORROWED` / `REPAID` and each treasury's.

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
- operating_expense — for an `INCOME` leaf, TRUE routes it into the `OPERATING_EXPENSE` subtotal, below gross
  profit, instead of `COST_OF_GOODS` or `REVENUE`: a cost no operation's run weighs, such as a module's upkeep, administration,
  wear and research (`FINANCIAL_MODEL.md`, principle 6). Signed like `tax`: a cost leaf adds, and a revenue leaf, a gain
  such as `DISPOSAL_GAINS`, subtracts. Operating income is the derived `gross profit − operating expense`. Unused for
  cash-flow and balance leaves.
- balance_class — for a `BALANCE` leaf, its `Enums.BalanceClasses` member (prefix `BALANCE_CLASS_`):
  `ASSET`, `LIABILITY`, or `EQUITY`. Routes the leaf into the assets, liabilities, or equity subtotal.
  Unused for `INCOME`/`CASH_FLOW` leaves (leave blank).
- tax — for an `INCOME` leaf, TRUE routes it into the `TAX` subtotal (signed: `revenue` TRUE adds,
  FALSE subtracts) below operating income, instead of `REVENUE`/`COST_OF_GOODS`; net income is the
  derived `operating income + TAX`. Unused for `CASH_FLOW`/`BALANCE` leaves (leave blank).
- account — `Enums.Accounts` member (prefix `ACCOUNT_`): whose account the item is. Blank is the
  facility's own; `GOVERNMENT` and `CORPORATE` are its player's treasuries, booked at the player's
  administrative center but never that facility's (`FINANCIAL_MODEL.md`, "The accounts"), such as
  `TAX_REVENUE` and `GOVERNMENT_CASH`. The subtotals sum every account booked at an entity; the Budget
  tab shows each treasury's items apart from the facility's.
- keyed_by — `Enums.Counterparties` member (prefix `COUNTERPARTY_`): what the item is kept per. Blank
  is kept once; `FACILITY` and `PLAYER` keep a line of the item for each facility or player it moves
  money to or from, such as a treasury's `GOVERNMENT_FUNDING_PAID` by the facility funded and
  `APPROPRIATIONS_PAID` by the agency, each line coming into being with its first booking, so no row
  names a facility or a player (`FINANCIAL_MODEL.md`, "Line items"). A line follows its item in every
  other field.
