# astropolis_public
This repository contains the *moddable* part of Astropolis, which includes all content data, GUI and game AI.

Astropolis is a simulation game that explores human expansion and evolution in our own solar system. It is an early stage, open development project created by Charlie Whitfield built in the [I, Voyager](https://www.ivoyager.dev/) solar system simulation using the [Godot Engine](https://godotengine.org/).

Astropolis will be highly moddable. It is NOT open source!

### Astropolis Links
* [About page](https://t2civ.com/about/)
* [Homepage & dev blog (t2civ.com)](https://t2civ.com/)
* [Discussion subforum at I, Voyager](https://www.ivoyager.dev/forum/index.php?p=/categories/astropolis)
* [Twitter (@t2civ)](https://twitter.com/t2civ)
* [Facebook (/t2civ)](https://www.facebook.com/t2civ/)
* [Public repository containing content data tables, GUI, and game AI](https://github.com/charliewhitfield/astropolis_public) (this repository)
* [Public development builds (most definitely NOT alpha yet!)](https://github.com/charliewhitfield/astropolis_public/releases)

### Development Plan for Modding
In the future, our modding "software development kit" will be the [Godot Editor](https://godotengine.org/features/) with an Astropolis SDK add-on. You will be able to make changes, run the modified game directly from the editor, and then export the mod as a .pck file. This won't happen until we are much further in development.

### Content Data
Content data is defined in simple text data tables in I, Voyager ([ivoyager/data/solar_system/](https://github.com/ivoyager/ivoyager/tree/master/data/solar_system)) and in this repository (find in [data/tables/](https://github.com/charliewhitfield/astropolis_public/tree/master/data/tables)). Table loading is defined in [IVGlobal](https://github.com/ivoyager/ivoyager/blob/master/singletons/global.gd) as modified in [astropolis_public/astropolis_public.gd](https://github.com/charliewhitfield/astropolis_public/blob/master/astropolis_public.gd) (search "table").


Table row entities are *never* hard-coded in core Astropolis. But some tables (particularly those named "_classes") contain categories that are coded in GUI files, which are accessible and moddable. Cell values may be modified based on column header values for Default, Unit and Prefix. Row names are always globally unique. Tables include enumerations (text in Type INT columns) that may refer to a data table row number or an internal enum.


The I, Voyager table [README](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/README.txt) explains general table structure. This repository's table [README](https://github.com/charliewhitfield/astropolis_public/blob/master/data/tables/README.md) contains *very* rough work-in-progress notes on Astropolis content.

### Program Architecture
Astropolis has essentially a client-server architecture. AI and GUI are clients and communicate with the servers (the game internals) only via "interface" classes like PlayerInterface, FacilityInterface, BodyInterface, and so on (find in [interfaces/](https://github.com/charliewhitfield/astropolis_public/tree/master/interfaces)). Game AIs are subclasses of these interfaces: e.g., PlayerBaseAI, PlayerCustomAI. GUIs hook up to interface classes to get data or make changes, with care for multithreading since interface changes happen on the AI thread while GUI runs on the SceneTree main thread.


The interface/AI classes are composed with objects like Inventory, Operations, Population, Biome, and a few others (find in [net_refs/](https://github.com/charliewhitfield/astropolis_public/tree/master/net_refs)). These "NetRef" objects are optimized for network data sync.


It's very likely that the NetRef and Interface classes eventually will be ported to C++, becoming GDExtension classes. In true Godot-fashion, individual AI subclasses then can be coded in GDScript, C#, C++, or anything else. At some point (I assume) we'll want to interface with Python's AI libraries.
