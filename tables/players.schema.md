# Schema for players.tsv

Players are described in `players.descriptive.md`.


## Fields

- name (1st column) — Constructed per table instructions.
- player_class — One of POLITY, AGENCY, or COMPANY.
- start — Always TRUE (by default).
- part_of — If present, specifies that this player's population and activity are counted as part of another player.
- polity — National polity of the player.
- homeworld — Always Earth (by default).
- corporate_tax_rate — Game-start value: for a polity, its corporate tax, a share of the operating income of the private share of each of its facilities and its agencies' and companies' (`FINANCIAL_MODEL.md`, "Taxes"). Default 0.2.
- payroll_tax_rate — Game-start value: for a polity, its payroll tax, the share of every wage paid by its facilities and its agencies' and companies' that is withheld for its government treasury, from 0 to below 1. Seeded from recall at each polity's effective tax rate on labor in 2015, its taxes on labor income and its social contributions over what labor earned. Default 0.
- wealth_tax_rate — Game-start value: for a polity, its wealth tax, a share a year of what its residents hold past `wealth_tax_threshold`. Default 0: in 2015 no polity here raised more than about a tenth of a percent of its output by a tax on net wealth.
- wealth_tax_threshold — Game-start value: for a polity, the wealth past which its wealth tax falls, a share of its residents' mean wealth; 0 taxes all of it alike. Default 1.
- appropriation_share — Game-start value: for an agency, the most its polity's government treasury appropriates it, a share of that treasury's budget, which the base AI seeds as that budget's line (`FINANCIAL_MODEL.md`, "Budgets"). The agency's whole budget, which its facilities' funding lines divide. Seeded at each agency's 2015 budget over what its polity's government treasury took in a year over 2015's quarters in a game. Blank for players that are not agencies.
- provision_share — Game-start value: for a polity, what its government treasury spends on its residents' public provision, a share of that treasury's budget, which the base AI seeds as that budget's line (`FINANCIAL_MODEL.md`, "The treasuries' budgets"). It buys the public share of each want (`wants.tsv`, `public_share`) for every class alike as far as it goes. Seeded from recall at what each polity's governments spent in 2015 on health, education, public order and general public services less interest, over their revenue. Blank for players that are not polities, and for a polity that provides none.
