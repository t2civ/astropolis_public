# Schema for technologies.tsv

Each row is a technology: an area of knowledge or capability, in any domain of human knowledge and function, that a player holds at some level and advances in, never discovers. The design is the development repository's `TECHNOLOGY_MODEL.md`. What each technology is in the world is in `technologies.descriptive.md`. The table is self-contained: it names no operation, module, population or player, and those name the technologies that enable and improve them. Within the table, each technology names the technologies it builds on, its sources, never what it enables.

Every value here is immutable. What a player holds is state, seeded at game start elsewhere.

**Levels are measured in years.** A year of a technology is the progress the world made in it in a year at the start: its pace then, at the research and practice spent on it then. So a player two years behind in rocketry and two behind in number theory are each where the world stood two years earlier, and a technology's runway is how many such years it has left. A technology's effects (what an operation's efficiency gains, an hour's labor saves, a population's aging slows) are given per year of its progress by whatever names it.


## Fields

- name (1st column) — Technology name per data table instructions, `TECHNOLOGY_` prefix: the name the field goes by in the world, popular or technical, such as `GAME_THEORY`, `QUANTUM_GRAVITY` or `MOLTEN_REGOLITH_ELECTROLYSIS`.
- area — TABLE_ROW `areas.tsv`, the research area the technology is shown under and its research allocated by, and through the area its knowledge domain. Never what the technology does or how it bears on another.
- openness — FLOAT in years: the median of how far the technology can advance past the start on the foundations the start provides, in years of progress at the start's pace. Small for a field thought mostly done, as general relativity is, or stuck until other technologies open it, as fusion power is; large for a field wide open, as materials science is. The technology's sources raise it as they advance.
- openness_spread — FLOAT: the standard deviation, in orders of magnitude (log10), of the lognormal each game draws the technology's openness from, so how uncertain its open-endedness is. 0.3 is a factor of two either way at one standard deviation, 1 a factor of ten.
- practice — FLOAT from 0 to 1: how much of the technology's advancement comes through practice, the work of the operations that name it as practiced (building and flying rockets, running fabs, treating patients), against research alone. 0 for pure theory, about 0.5 for engineering, toward 0.85 for crafts and production know-how. Where it is large, research without practice advances the technology slowly, and a level its practice stops holding erodes.
- diffusion_time — FLOAT in years: how long a follower's gap behind the technology's frontier takes to close by a factor of e, at full absorption and open access. A few years for published science, one to three decades for what is advanced mostly in practice, longer for tacit, proprietary or secret know-how, as Earth's adoption lags run (Comin and Hobijn). A player's absorption and its access, which sanctions cut, set how much of it a follower gets, and so how far behind a follower settles and how fast it gets there.
- sources — ARRAY[TABLE_ROW] of technologies, `TECHNOLOGY_` prefix: the technologies this one builds on, whose progress opens its potential (`TECHNOLOGY_MODEL.md`, "The network"). Never itself: what a technology's own progress leaves of it is its openness.
- source_links — ARRAY[VECTOR4], one for each of `sources`, in the same order. Each holds four floats delimited by commas:
  - impact — the median of how many years of this technology's potential one year of the source's progress opens, each at its own pace at the start.
  - impact_spread — the standard deviation, in orders of magnitude (log10), of the lognormal each game draws the impact from. 0.2 for a link well understood, 1 for one whose size no one can know.
  - delay — the median of how many years pass between the source's progress and the potential it opens here.
  - delay_spread — the standard deviation, in orders of magnitude, of the lognormal each game draws the delay from.


## Notes

1. Openness, practice and diffusion tend to go together. Codified knowledge is published, spreads in a few years, is advanced by research and kept in the record; tacit knowledge lives in people and plants, spreads over decades, is advanced by practice and erodes when practice stops. They are separate columns because the exceptions matter: large language models are practiced and yet spread in a few years, and nuclear weapons spread slowly because they are kept secret, not because they are hard to learn.
2. A speculative technology, such as a warp drive or mind uploading, has a small openness with a wide spread: little can be done on today's foundations, but a game's draw, and the advance of its sources, may open it.
3. Nothing in a row says whether a technology is basic science or applied engineering. That shows in where it stands among the sources, in what names it for its effects, in its practice and in its diffusion.
4. Links run both ways. Science opens applied potential, often decades later, as quantum mechanics opened semiconductors; and practice opens science, as steam engines opened thermodynamics, telecommunications information theory, and language models are opening cognitive science.
5. Typical links, as the table was first written: a close sibling `0.25,0.2,2,0.2`; a foundation `0.15,0.3,8,0.3`; science to its applications `0.15,0.4,15,0.3`; enabling engineering `0.2,0.25,4,0.25`; an instrument or new phenomena feeding a science `0.1,0.4,6,0.3`; a key dependency `0.4,0.3,5,0.3`; a revolution in science reaching its applications `0.2,0.6,30,0.3`; a weak link `0.04,0.5,15,0.3`; and a speculative one `0.01,1,40,0.4`, small but an order of magnitude uncertain, as string theory's bearing on any engineering is.
6. A row's impacts summed say how fast its potential grows when every source advances at its start pace. Below one, the technology matures unless its openness is large; above one, its potential outruns it, and its research and practice set its pace.
7. The links are what was expected at the start, and each game draws its own impacts and delays from them.
8. Values are from recall, a starting point for the network to be run against (`TECHNOLOGY_MODEL.md`, "Proving it").
