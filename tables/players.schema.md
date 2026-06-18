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
