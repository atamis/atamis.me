---
title: "Intentional Limit Breaks in Video Games"
date: 2019-01-14T11:58:20-08:00
---

When building consumer software, it's a widely held belief that the software
shouldn't crash, shouldn't hang (or ignore user input), and should generally
remain "in control." Users don't like software that crashes and loses their
progress, and they don't react well to software that freezes: they tend to spam
buttons, making the problem worse.

This is just as important _and much harder_ for video games. Video games are
among the most complex and demanding software being produced commercially, and
they're likely the _most_ complex and demanding software the average consumer will
ever run. They have to simulate a large and engaging game world, while also
rendering the world and all its graphical effects to the screen, at 60 frames
per second: 16.5ms per frame. They also need to load vast quantities of data
from unreliable consumer grade storage devices, and some games set themselves
the task of eliminating load screens _and streaming the data live._ Multiplayer
games must also coordinate complex real time protocols with game servers.
Additionally, games only recently started to take full advantage of the extra
cores modern CPUs have.

Professionals have a somewhat different perspective. In this context,
"professional" means people who work as "software technicians" in a professional
capacity, even if their job and expertise is not necessarily software. This
would be 3D graphics experts, audio technicians, data scientists, and
programmers. Their software is designed for professional use, and its
professional users have different standards. Software which crashes is bad, but
managable: just save a bunch. Software which hangs is par for the course: the
tools of programmers regularly use entirely non-interactive user interfaces
(like CLIs).

But let's address the "in control" issue. Consumer grade software tends to have
limiters on it. It will only do so much so fast, because if it went faster or
did more it would be prone to crashes or freezes. Professional grade software
has no limiters. If you throw too much data at it, it'll happily spend 14
hours chugging away, or it'll happily consume all available system resources
doing whatever stupid thing you told it to. Professional software assumes you,
the user, is a professional, and that _you know better than the software.[^6]_

The same limits can be easily found in games as well. The most common are
"physics limits." Physics systems are common in games looking for some easy
realism, but even the most efficient physics system can only calculate so many
physical interactions in the 16.5ms, so games will put a limit on the number of
interactable physical objects. Some limit them in level design--designers can
only place so many in the same scene--or by number (trying to dynamically spawn
more than the limit removes old objects). If the physics system takes too long,
the frame rate of the game will slow down, producing a bad play experience[^1].
Almost every game has stress tested the level size, the physics system, the
number of AI agents, and the number of human players to find the theoretical
maximum allowed, and then places hard limits to prevent the game state from
going out bounds and degrading the play experience.

But what if there were games that didn't do that. What if there were (pardon the
phrase) "professional" games that didn't have those limits and let you do
whatever stupid thing you wanted. What are those games like?

# Path of Exile

Path of Exile is an action RPG developed by Grinding Gear Games as a spiritual
successor to Diablo 2. It features always online top down 3D action backed by an
incredibly complex and detailed combat system. Although the broad strokes are
very familiar, it has some surprises, but the real draw is the _detail_ and
_consistency_ of the system. Path of Exile's designers see the combat system and
accompanying character creation and advancement system as integral to the game
experience, and the true gameplay of Path of Exile is arguably not killing monsters but
building and optimizing characters. The process of theory-crafting a new and
innovative build, creating the character in game, experimenting with variations,
and sharing your discovers with other players is core to the replayability of
the game. The system is so complex that even experienced players haven't
explored it fully, and don't fully understand the system in its entirety.

Path of Exile is a complex system, so breaking it is not very hard. The system
breaking is still considered a problem by the developers, so they tend to fix
the issues, and prevent these problems. They usually leave the "bug" in the
game for at least a while, because generally you can only hurt yourself with
these setup.

One of the easiest ways to "break" the game is by killing your FPS. There are a
couple of ways to trigger abilities in the game, and for a while, these triggers
had no cooldown. You could use these triggers to activate way way more abilities
per second than the developers expected, and by using trigger graphically
intense spells in this way, you can shred your FPS. You can also use effects
that trigger on kill and are strong enough to kill neighboring enemies to kill
very large numbers of enemies _instantly_ in a single frame, triggering hundreds
of ability effects, and causing the game to hang on that single frame for up to
a second before play resumes.

The solution was to add a cooldown, limiting the number of abilities that can be
cast per frame. There was, however, a second more insidious way of breaking the
game. Although the frame rate issue was under control, the "hit-rate" problem
wasn't. Although the number of abilities was much reduced, there were some
abilities that caused many "hits" per spell cast, and which persisted,
causing that number of hits per second for up to 10 seconds. By constantly
triggering those abilities, you can reach a very high number of hits per second.
This, in and of itself, would not be a problem: The game is well optimized for
hits as they are the main way of doing damage. The problem is with a particular
effect that happens on hit, "Poison"[^2].

> It is not enough to simply defeat the monsters in Path of Exile. We must now
> turn our fight to _the game server itself._

Poison is simple, you hit the enemy a couple of times, they gain a poison stack
every time you hit them, and each poison stack does damage and has duration
independent of each other. There is also an effect that reads, "5% increased
Poison Duration for each Poison you have inflicted [in the last 4 seconds]."
Because the build inflicts a stack of poison in hit, and it constantly hits
extremely fast, it builds up more poison stacks than the developers ever expected you
to have, and it builds them up on every single enemy in range. It is not
abundantly clear exactly why this is a problem for the game server, but it is.
It's possible that the server simply can't handle that many Poison stacks and
all the spell casts at the same time, the game simulation slows down, and the
server gets killed by a crash detector for taking too long on a single frame.
It's also possible that all the poison stack data has to be pushed to the game
client, and that if the client takes too long accepting all the data, the game
server assumes something has gone wrong, and crashes itself. Either way, the
instance you were in is gone, any resources you spent opening the area are
consumed and not returned, and anybody connected to the instance (you and up to
5 friends) are disconnected in what the game calls an "Unexpected Disconnect",
but which everybody involved should have seen coming.

Although this build is incredibly strong and very easy to both build and play,
it simply isn't viable because it constantly crashes the game servers. Attempts
to mitigate this by introducing previously unused (in this build) _on kill_
effects do not help it very much. Because of the server architecture of the
game, the crash is isolated, and only hurts you. It doesn't affect other
player's instances.

In fairness to Path of Exile, this build is almost designed to break the game
and crash servers, and most builds and most players don't stress the game
anywhere near this much. However, the game still lets you do this, and trusts
that if you make a character that crashes the game servers, you'll know what
you're getting into. Nonetheless, theorycrafters have to take into account what
the game client and the game server can handle, because the developers won't
always be looking over your shoulder making sure you aren't breaking anything.


# Minecraft

Minecraft is well known for a lot of things (sandbox-style construction,
RPG-like combat progression, infinite exploration across 3 worlds, 9 year olds),
but also for its Turing-completeness: using redstone, you can implement logic
gates from NOT all the way up to a full computer. It's a difficult medium to
work in: there's no native copy and paste, so you have to manually build
everything, and the tick rate low, so the resulting computer is very slow, but
there's another consideration to make, one that isn't part of the game design.

The intended design is pretty simple: signals and inverters. However, Minecraft
is an infinite game. The game world is split into vertical chunks. Chunks are
stored individually on disk, and streamed into the game live. You can see this
happen if you run the game on a slow disk: moving quickly will quickly get you
to the edge of loaded chunks and the game simply doesn't render chunks it hasn't
loaded, and shows empty space instead. Of course, if a chunk isn't loaded, the
game simulation can't run all different simulations, including redstone.
Redstone isn't very compact, so it's easy to accidentally build a computer
larger than normally loaded zone. Even if it's _mostly_ in the loaded area,
computers are generally not very resistant to suddenly losing bits of
themselves. You also need to be right next to the computer to work, so actually
using the computer to automate your remote bases, or something, is not possible.

There are 2 solutions. The first is to adapt your computer design to limit its
horizontal foot print, pushing components above and below ground rather than
spreading across the landscape. This still limits the ultimate size of your
computer, and specifically the maximum line size. You aren't going to be
building a 32 bit computer in Minecraft (not that you would necessarily want to).
In this context, implementation details in the game engine seriously impact on
your gameplay, and your designs. The game doesn't limit the mount of redstone
you can use, or its complexity, but you need to work within unstated
restrictions to make anything larger than a trivial circuit. It's really cool
that this capability is in the game, but you have to pay attention to a lot of
unspoken _technical limitations_ rather than the intended game design.

The other solution is using mods to allow you to force the server to always
simulate those chunks. Eventually, you'll run into the limit of the Minecraft
server's ability to simulate chunks, but this limit is also explored with the
player limit: the server has to simulate all the chunks around every player. The
Minecraft server has a default player limit, but it's well understood that this
is just an average, and weaker than average servers may need to lower the limit,
and much stronger servers (more RAM, SSDs, good CPUs) can raise the limit
substantially. Of course, splitting the client and server processing onto
separate machines is a good idea, although thanks to modern GPUs (and the fact
that the Minecraft standalone client just uses the server under the hood), it
likely doesn't matter too much.

# Dwarf Fortress

Dwarf Fortress is an _interesting_ and _Fun_ game about designating a fortress
and guiding your small army of dwarves to build, excavate, and construct, with
the ultimate goal of surviving in an environment as hostile as you want it to be.
It's played on a 3D voxel grid much like Minecraft, but where Minecraft is
infinite, but with reasonably few simulation aspects, Dwarf Fortress is finite,
but vastly more complex simulation aspects. Dwarf Fortress reports 2 FPS
numbers, graphical FPS and simulation FPS. Graphically, Dwarf Fortress is
_very_ simple, so keeping graphical FPS capped is easy. Dwarf Fortress'
simulation is frame locked, and the game involves a lot of waiting, so
maximizing simulation FPS makes the game go very fast and makes the waiting
easier. To avoid overshooting in time, and to avoid over-consuming CPU resources,
simulation FPS is usually capped at 200, but very quickly dips below it as the
game gets more complicated, and the simulation more CPU intensive. Late in the
game, the simulation gets _very_ slow, and the player base aggressively seeks out
methods of optimizing their game installation and gameplay to get the game to
run at a reasonable pace.

One of the biggest contributors to simulation time is actually map size. It
seems like large portions of map has to be by the simulation code visited in
some respect, so larger maps are slower. Another major contributor is number of
allied dwarves. Each dwarf is a very complex actor in the world, capable of most
gameplay relevant actions, but also influenced by physiological and
psychological simulations. They're constantly moving, so they regularly pathfind
around the map. The game caps the number of dwarves in any given game at 200,
but that is configurable. Unfortunately, the number of _animals_ is not
capped, so it's possible to enact a "catsplosion", rapidly breeding cats, then
releasing them into the world to massively reduce your own simulation FPS.

Of course, all these dwarves and animals and enemies need to move around the
game world, for which they use pathfinding. Pathfinding tends to be slower on
larger and more complex maps, so players will limit the amount of area they'll
excavate, or block off areas they don't need any more just to speed up
pathfinding.

Water is also very slow to simulate, especially water features which generate
mist, making them something of a status symbol: to have one in your game is a
sign that you either don't care about simulation FPS, or have such a powerful
computer that a water feature is no big deal.

Of course, Dwarf Fortress also features complex manufacturing chains and many
relevant items which can sit in stockpiles, in bins, and be carried around by
actors. Items on the ground impact pathfinding, and large numbers of items makes
it harder for the game to calculate hauling and stockpile management, so
minimizing the items you generate, and destroying items you don't need, is a
good way of improving your simulation FPS.[^3]

These techniques, and the overarching desire for better FPS, have shaped the
community perception heavily, and guides and blueprints for Dwarf Fortress almost
always consider the performance characteristics of their advice and designs.
However, in moment to moment gameplay, it's not terribly important. Players are
usually consumed by shorter term issues, like feeding and growing their
fortress, to let long term concerns like end game FPS to concern them.

# Factorio

Factorio is yet another simulation game, and like Dwarf Fortress, it's also
frame-locked, but it's more graphically rich than Dwarf Fortress, and locks
graphical FPS and simulation FPS together. Where Dwarf Fortress is _playable_ at
low simulation FPS and high graphical FPS (and it's pausable, allowing you to
easily issue commands even in heavily overloaded forts,) Factorio at low FPS is
almost unplayable. You control a single character (unlike Dwarf Fortress, where
you are an ethereal overlord), and the character must be present at a part of
your factory to issue commands to it, so low FPS means your factory will produce
items slowly, your research will go slowly, and your character and commands will
react slowly.

This makes FPS a somewhat more pressing issue. Luckily, the Factorio developers
are aware of this, and they take game optimization very seriously, and provide
in game tools that players can turn to if they reach a scale where performance
truly matters. Most players may _care_ about performance, but don't need to
consider it seriously at the scale they play at.

Factorio is a game primarily about mining resources from the ground,
transporting the resources to factories for refining, taking those materials
through several cycles of refinement, assembly, and intermediate products,
before producing highly refined materials that science labs can use to do
science, advancing your research, and ultimately allowing you to launch a rocket
into space[^4]. The research can improve every aspect of that
process, and provide quality of life upgrades to you personally, making almost
the entire tech tree worthwhile. However, you can easily complete the tech tree
without even glancing at the FPS counter, so only serious players who are
competing with themselves and others to produce the maximum amount of research
possible, even when that research isn't useful anymore, to see who can build the
best factory.

One major feature of Factorio is its enemies. The enemies are attracted to the
pollution your factory produces, and attack in waves, necessitating the creation
of automated defenses, an ammo production factory, walls, etc. However, enemies
are pretty FPS intensive to simulate, so many people disable them entirely to
prevent them from slowing the game down.

Factorio is primarily a game about moving items around the world, and
consequently has several methods of doing so: Trains, Belts, and Bots. Trains
carry very large quantities of items very quickly, but require special tracks,
stations, fuel, and unloading systems. Belts are conveyor belts on the ground
that carry items dropped or placed on them, and bots are flying robots that can
pick up and carry items between special containers. Transitioning between
these systems is relatively easy, and also easy to move items from these systems
to individual factory pieces for processing. When items are in trains, they
don't count as individual actors, only the train does, making them very FPS
efficient for moving items around. Similarly for bots. They're very highly
optimized, and when in storage or being carried by bots, the game engine only
needs to consider individual bots. Belts, however, have to consider every item
on them individually. In a large factory, this can be hundreds of thousands of
items updated individually, making conveyor belts very inefficient. Thus, for a
long time, belts were essentially abandoned, much to the chagrin of portions of
the player base. Bots were simply too efficient, and belt based factories
couldn't compete with bot based ones in terms of scale.

Luckily, Factorio's developers were aware of this discrepancy, and recently
rectified it with a serious efficiency improvement to belts, bringing them
equal to bots in terms of FPS efficiency. Suitability, convenience, and
throughput potential are still important arguments to the community (but not
this article).

Another area of inefficiency was fluids. From crude oil to refined oils,
petroleum, plastic, lubricant, and sulfuric acid, Factorio has a complex
manufacturing web of fluids and refineries. Unfortunately, fluids are
transported via pipes using a crude and somewhat obscure fluid simulation.
Unfortunately, it was also a very inefficient fluid simulator, and refinery
complexes built as intended by the game tended to be very inefficient for their
size and throughput, making them a regular pain point for very large factories.
In fact, for a long time, it was more efficient to barrel the fluids and
transport them with bots rather than use actual pipes. This was terribly
inconvenient, requiring large barreling and unbarreling stations at every
refinery component, and a very spread out refinery design. It was more efficient
for simulation speed, so people did it anyway.

Fluids are also relevant for power generation. Factorio has 3 different power
sources, Steam, Solar, and Nuclear. Steam and Nuclear both use energy sources to
boil water to steam, and then steam engines or turbines to convert the steam
into electrical power. Not only was steam a fluid, but the heat pipes Nuclear
reactors used to distribute heat to their boilers were coded as fluids as well,
making both of these techniques very FPS inefficient. Mining the uranium to fuel
the nuclear reactors also requires pumping sulfuric acid through the mining
installations, another very expensive process. Solar, on the other hand,
as essentially a multiply instruction, counting the number of panels and
multiplying by the current solar output. Although _very_ space inefficient
compared to nuclear, Solar is and will likely continue to be the go to power
source for very large factories for the foreseeable future. Luckily, a rework of
fluid transport is coming soon, promising both more accurate and more efficient
fluid simulation.

Although we've been discussing "very large" factories, and how much the game
cares about optimization, it's surprising how quickly your FPS falls even at
moderate factory sizes if you don't pay attention to these issues. If have a
moderate belt based factory powered by several large nuclear reactors, you can
see serious FPS dips.

# Conclusion

Conventional wisdom says that these game should stop the player before they get
to this point: hide the warts and inefficiencies behind hard limits so players
don't have to consider these issues: so you don't have to be a software engineer
to understand the game and do amazing things. I would assert, however, that
there _is_ a market for games which don't do that. Games where you can rip the
limiters off and really let the game run wild, or games which don't have limits
in the first place, and let you do whatever stupid crazy thing you want, as long
as you can design it to run fast enough, or are willing to wait long enough.
Games that give players the tools to, within the context of the game, do what
they want how they want. Games which essentially let players take ownership of
their creations, to deal with the game engine and the computer on their own
terms, unrestricted by the conventional wisdom that "games shouldn't slow down
or crash." Mods are definitely part of this (3/4 of these games allow modding in
some capacity), but they let you reach and exceed conventional limits _in the
base games themselves._

Whenever you start engaging with games like this,
_feels_ like you're doing things the game designers and programmers never
intended, that you have gone even further beyond what was expected, and into
uncharted territory[^5]. This likely isn't the case: the developers probably to
a certain extent expect someone like you to play the game like this, but when
your FPS chugs, the server starts glitching, and you start thinking about
algorithms, Big O notation, and breaking limits, it can certainly feel like
you're in uncharged territory. That's really what this is about: a feeling of
real exploration and novel discovery, of interacting with and considering issues
that precious few other people have.

[^1]: Games tend to lock their game simulation to either the clock or the frame
    count. If locked to the clock, the game moves forward at the same speed
    regardless of the frame rate, producing choppy but playable games. If the
    game is instead locked to frame count, decreasing frame rates slows the
    entire game down instead, because everything moves the same amount per frame
    regardless of how fast the frames come. Frame-locked physics systems always
    know what their time slice is, but clock-clocked physics systems have to
    deal with simulation ticks potentially spanning much larger amounts of time
    than expected. If the physics system identifies collisions with naive
    collision detection code, a very large time slice can have the collision
    happen essentially between frames, leading to choppy _and glitchy_ gameplay.

[^2]: [Path of Exile - The Forbidden Build](https://www.youtube.com/watch?v=MWyV0kIp5n4) by OMGItsJousis.
[^3]: [Maximizing
    Framerate](http://dwarffortresswiki.org/index.php/DF2014:Maximizing_framerate)
    on the Dwarf Fortress wiki.
[^4]: Much has been made of the potential for the game to have a sequel, either
    in space or on another world (mods for both are available, I think), but in
    the base game, launching a rocket simply gives you "Space Science", allowing
    you to continue your never-ending quest for more science.
[^5]: This is part of what makes Minecraft's [Far
    Lands](https://minecraft.gamepedia.com/Far_Lands) so interesting. If you
    want to see a game visibly _break_ but try its best to keep chugging, or see
    game features that were _clearly_ not developer intended, that article and
    its attending pictures are a real treat.
[^6]: I usually see Consumer vs. Professional software as an question of UI, and
    of discoverability and ease of use vs. productivity. This is most apparent
    when comparing, say, Apple's iOS with Maya, Blender, or the all programming
    languages. It's also very apparent, however, in World of Warcraft UI trends,
    where the difference between the stock consumer UI and the custom UIs built
    by top end raiders is _total:_ they have nothing in common.
