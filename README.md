# astropolis_public
This is the public (moddable) part of Astropolis.

Astropolis is a simulation game that explores human expansion and evolution in our own solar system. It is an early stage, open development project created by Charlie Whitfield built in the [I, Voyager](https://www.ivoyager.dev/) solar system simulation using the [Godot Engine](https://godotengine.org/).

Astropolis will be highly moddable. It is NOT open source!

For information about Astropolis, go [here](https://t2civ.com/about/).

### Links
* [Homepage & dev blog (t2civ.com)](https://t2civ.com/)
* [Discussion subforum at I, Voyager](https://www.ivoyager.dev/forum/index.php?p=/categories/astropolis)
* [Twitter (@t2civ)](https://twitter.com/t2civ)
* [Facebook (/t2civ)](https://www.facebook.com/t2civ/)
* [Public repository containing content data tables, GUI, and game AI](https://github.com/charliewhitfield/astropolis_public) (this repository)
* [Public development builds (most definitely NOT alpha yet!)](https://github.com/charliewhitfield/astropolis_public/releases)

### Development Plan for Modding
In the future, our modding "software development kit" will be the Godot Editor with an Astropolis SDK add-on. You will be able to make mod changes, run the modified game directly from the editor, and then export the mod as a .pck file. This won't happen until we are much further in development. 

### Quick Note on Program Architecture
Astropolis has essentially a client-server architecture. AI and GUI are clients and communicate with the servers (the game internals) only via "interface" classes like PlayerInterface, FacilityInterface, BodyInterface, and so on (find in directory interfaces/). Game AIs are subclasses of these interfaces. GUIs hook up to these interface classes to get data or make changes (with some care for multithreading since interface sync happens on the AI thread while GUI runs on the SceneTree main thread).


The interface/AI classes are composed with objects like Inventory, Operations, Population, Biome, and a few others (find in directory net_refs/). These "NetRef" objects are optimized for network data sync.


It's very likely that the NetRef and Interface classes eventually will be ported to C++, becoming GDExtension classes. In true Godot-fashion, individual AI subclasses then can be coded in GDScript, C#, C++, or anything else. At some point (I assume) we'll want to interface with Python's AI libraries.
