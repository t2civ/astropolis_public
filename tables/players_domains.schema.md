# Schema for players_domains.tsv

This Entity x Entity table seeds each player's technology at simulation start in 2015 by knowledge
domain (`domains.tsv`): how far behind the frontier it stood in the domain's technologies, and how
the research its funders allocate is shared among the domains (`TECHNOLOGY_MODEL.md` in the
development repository, "Research", "The step, as built"). Its rows are domains and its columns players, transposed on import to
table[player_type][domain_type].


## Table Data

The data type is ARRAY[FLOAT]; each cell holds 3 values delimited by semicolons:

- 1 value, with an inline `y` — the research's gap: how far behind the frontier the player's
  scientists and engineers stood, in years.
- 1 value, with an inline `y` — the practice's gap: how far behind it the player's economy worked
  on average, in years.
- 1 value — the research's share: of the research the player's funders allocate, a polity's public
  research and an agency's research, what goes to the domain, spread evenly over the domain's
  technologies; its business research goes where its operations practice. A player's shares sum
  to 1.

A player's gap in each of the domain's technologies is its two gaps blended by the technology's
`practice` share (`technologies.tsv`), the research's weighing as far as its advance comes from
research; `technologies` and `technology_gaps` in `players.tsv` name the technologies where it
stands apart. The frontier at the start is the best player's level in each technology, so a gap is
read against the leader's.

Every polity fills every domain. An agency fills the domains it researches and holds its polity's
levels in the rest, blank cells; its shares sum to 1 over the domains it fills.

The gaps are seeded from recall: the research's from where each nation's science and engineering
stood; the practice's so that its operations, drawing their work at their labor factors
(`labor_saving` in `operations.tsv`), take what an hour made in each of its sectors against the
USA's in 2015 past what its schooling gives, and its plant draws about the USA's share of the work
its people offer (`tests/calibration/seed_audit.py`): the goods domains' (Industry, Materials,
Chemistry and Energy) from its manufacturing's labor productivity, Society's from its services',
and farming's, the widest, named by technology in `players.tsv`, split between its industrial and
traditional techniques. The shares are seeded from recall of each nation's government research by
field, defense, health, energy and the sciences above all, and an agency's by program.
