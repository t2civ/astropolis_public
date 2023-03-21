# astropolis_public
This is the public (moddable) part of Astropolis.

Astropolis is a simulation game that explores human expansion and evolution in our own solar system. It is an early stage, open development project created by Charlie Whitfield (that’s me!) built in the [I, Voyager](https://www.ivoyager.dev/) solar system simulation using the [Godot Engine](https://godotengine.org/).

### Quick links
* [Homepage & dev blog (t2civ.com)](https://t2civ.com/)
* [Twitter (@t2civ)](https://twitter.com/t2civ)
* [Facebook (/t2civ)](https://www.facebook.com/t2civ/)
* [Discussion subforum at I, Voyager](https://www.ivoyager.dev/forum/index.php?p=/categories/astropolis)
* [Public repository containing content data tables, GUI, and game AI](https://github.com/charliewhitfield/astropolis_public)
* [Public development builds (most definitely NOT alpha yet!)](https://github.com/charliewhitfield/astropolis_public/releases)

### What is Astropolis about?
It is the story of becoming a Kardashev Type II civilization<sup>1</sup> in two installments. In the first, we’ll see off-Earth mining and manufacturing, interplanetary economies, artificial intelligences (of various sorts), O’Neill cylinders and other space habitations, and humanity on its way to becoming multiplanetary, or non-planetary. And in the second: general artificial intelligences, virtual and other kinds of humans, planet harvesting, star lifting, and a realistic Dyson swarm. These lists are only possibilities, however, as civilization may evolve in different directions. The two installments are presently code-named "Outward Bound" (borrowed from [Isaac Author](https://www.youtube.com/@isaacarthur3209)) and "K2."

In Astropolis, you start in the present day as a single organization, either a public space agency or a private space company. However, your organization will morph, split and give rise to new entities over time. When this happens, you may choose to become one of these new branches of humanity: perhaps a newly independent Mars colony, or something quite different and not-exactly human. There are no victory conditions per se, but there are many possible achievements involving population, economy, energy (the Kardashev scale), manufacturing, constructions, computation, information, biomass and biodiversity. You are free to pursue either competitive or cooperative approaches. However, many achievements are about whole solar system metrics.

“Space is big. Really big.”<sup>2</sup> Our solar system can support more humans than appear in most sci-fi representations of whole galaxies. Quadrillions, easily (considering only the biological kind). What does such a civilization look like? That’s the question I’m asking in Astropolis. Reality gives us interesting game challenges and scope. The [Rocket Equation](https://en.wikipedia.org/wiki/Tsiolkovsky_rocket_equation) is your foremost hurdle *from an economics point of view* (don’t worry, we’re not designing rockets!). We’ll see settlement of nearby star systems in K2, but speed-of-light communication limits your active engagement to only one star system at any time.

<sup>1</sup> A Kardashev Type II civilization consumes energy similar to the Sun’s total luminosity, about 3.8 x 10<sup>26</sup> W. Or, in Carl Sagan’s extended scale, Type 2 is defined at 10<sup>26</sup> W. This is only one of many ways to measure your progress in Astropolis.

<sup>2</sup> “…You just won’t believe how vastly hugely mind-bogglingly big it is.” Attribution to Douglas Adams, who was also a strong proponent of the use of footnotes.

### Is Astropolis moddable?
Absolutely! A large part (but not all) of Astropolis’ data and code is exposed and moddable, including all content data, GUI, and game AI. This part is maintained in a GitHub public repository [here](https://github.com/charliewhitfield/astropolis_public). Content is defined entirely in simple .tsv data tables, which means you can mod entirely different solar systems, different players, different resources, different industrial processes, or virtually anything else. I’m especially excited to open up the AI code. Let’s face it, game AIs are still largely terrible at the grand and strategic (non-twitch) levels. I think I can do better in Astropolis. New AI approaches are available. By exposing the AI code, I’m enabling you (the fans and modders) to push me where direction might be needed, or to do it better yourself if you like.

### How far is it in development? When will it be released?
Astropolis is in early development. The underlying solar system simulation (I, Voyager) is quite advanced. Resource, manufacturing, economic, technological, social and cultural models and other parts of Astropolis are at different stages, some (literally) on the drawing board. Realistically, official release of the first installment, Outward Bound, is several years in the future. My hope for 2023 and 2024 is to create at least an interesting simulation. From there I expect a year or more of effort to go from simulation (which may feel a bit sterile) to an immersive game experience.

### What do I mean by "open development"?
I’m sharing the development process via [dev blogs at t2civ.com](https://t2civ.com/), a discussion [subforum at I, Voyager](https://www.ivoyager.dev/forum/index.php?p=/categories/astropolis), a live view of the [public portion of the code base](https://github.com/charliewhitfield/astropolis_public) (the moddable part), and periodic [downloadable development builds](https://github.com/charliewhitfield/astropolis_public/releases) (free, as you wouldn’t want to pay for these right now ;-)). To be clear, Astropolis is NOT open source. It’ll be a game for sale when it is ready.

### What is the relationship between Astropolis and I, Voyager?
[I, Voyager](https://www.ivoyager.dev/) is a free, open-source platform for building games or other apps in a realistic solar system (which is itself built on the free, open-source Godot Engine). My intention is for I, Voyager to become a community project over time, although (sadly) I’m the only contributor at present. Astropolis is a for-profit game that I am building on the I, Voyager platform.

### What kind of art/graphics should you expect to see?
I’ll be hiring artists very late in development. In the meantime, expect some interesting “programmatic art” and shader work from me. Our site’s header image is one! ([What is that, anyway?](https://www.ivoyager.dev/2023/03/16/new-version-v0-0-14-is-out/#abstract)) See also my [Saturn Rings in I, Voyager](https://www.ivoyager.dev/2023/03/16/new-version-v0-0-14-is-out/#rings). As a general rule, expect to see a lot of procedural visuals in addition to fixed art assets. If strategic views showing tens of thousands of freighters in their Hohmann transfer orbits excites your imagination, then this is a game for you!

### What’s coming in the dev blog?
I’ll delve more deeply into specific areas of Astropolis. I’m thinking roughly every other month. Some likely topics:

* The Resource Model. How do we account for all of the iron in the solar system? What is the right level of resource abstraction?
* The Economics Model. Is this the Austrian School, or what? Futures contracts: an overcomplication, or a simplification for you and the game AI? Have you seen the price of Bitcoin lately?
* The Science, Technological and Engineering Models. How can we be “realistic” in some way and still surprising (which is, to be fair, realistic) about future advancement? 
* The Biological Model. How much biomass can the solar system support? How do we model biodiversity? Are humans evolving and what might they evolve into? Do we need biology at all?
* Evolution, broadly speaking. How does population size and structure affect evolution? Does evolution have a direction? How do we model other, non-biological, kinds of evolution: technological, political, economic, social and cultural?
* Program architecture. OOP or data-centric, or a bit of both? How am I fencing off the game AI, GUI, and you the modder from internals? And how does this relate to design for multithreading and multiplayer?
* Progress reports, from time to time.
* And whatever else I feel like… Post-scarcity societies? The Fermi Paradox? Who knows?

### How can you help?
Please spread the news and say hi on [our subforum!](https://www.ivoyager.dev/forum/index.php?p=/categories/astropolis) It’s quite a road ahead and I can use the encouragement!
