# Schema for players.tsv

Players are described in `players.descriptive.md`.


## Fields

- name (1st column) — Constructed per table instructions.
- player_class — One of POLITY, AGENCY, or COMPANY.
- is_start — Always TRUE (by default).
- part_of — If present, specifies that this player's population and activity are counted as part of another player.
- polity — National polity of the player.
- homeworld — Always Earth (by default).
- tax_rate — Income-tax rate (fraction of operating income) levied on the private sector of this player's facilities. Default 0.2.
- appropriation_share — Game-start value: for an agency, the most its polity's government treasury appropriates it, a share of its polity's income, which the base AI seeds as that budget's line (`FINANCIAL_MODEL.md`, "Budgets"); a share of the polity's income, not of its government's budget, until payroll and wealth taxes give the government a revenue to share. The agency's whole budget, which its facilities' funding lines divide. Seeded at each agency's 2015 budget over its polity's income at the start. Blank for players that are not agencies.
