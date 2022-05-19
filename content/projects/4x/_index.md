+++
title = "4x Game"

[header]
src = "/images/4x/4x_mid.png"
alt =  "An early 4x game."
+++

4x is an unpolished strategy game reminiscent of Civilization and Creeper World.
Built by Nick Care, Azrea Amis, Robert Tomcik, and Kirk Pearson, it was
developed under a strict deadline between February 10th and March 16th of 2016.
<!--more-->
It was the first game the group made together (see the
[second](/games/hexdecks)) and does not present an entirely coherent or bug-free
experience. It also eschews almost all in-game instruction, so I've included the
instruction manual below.

## <a href="/downloads/4x-windows.zip">Download for Windows</a>

[Github](https://github.com/atamis/4x)

![The start of a 4x game](/images/4x/4x_start.png)

# README - Game Instructions

Game Created by: Nick Care, Azrea Amis, Robert Tomcik, Kirk Pearson

## Goal

You have been assigned the task of making a new planets surface habitable
for humans. Harvest energy from nodes to warp in buildings and create a
spanning energy network. The goal of the game is to get 6 warp gates. This
will create a large energy burst that rids the surface of the planet of
any dangers.

# Controls

- Click on a hex tile to select it.
- Hit tab to select the next unit that has an action.
- Press shift to view the energy overlay. Nodes grant more energy when
  harvested, and the overlay is bluer closer to a node.
- After a unit is selected, you can command it to do 4 different things via
  the large buttons at the bottom of the screen. Starting from the leftmost
  button:
  - **Move** - This button will move a unit. Select a unit, click the "Move"
    button, then click where you want the unit to move. Alternatively,
    select a unit and right click where you want it to move. Each hex
    moved by a unit will consume 1 stamina.
  - **Build** - If you have a unit selected, this will open the build sub-menu.
    Click which structure you want to build and the unit will alert the
    Warp Gate to warp in the building on unit's hex.
  - **Scan** - This action will let the player search for energy nodes. It
    will reveal the energy levels of the tile the unit is standing on
    and all neighbouring tiles. The scan action will use 1 of the
    units stamina.
  - **Purify** - When clicked, the unit will attempt to purify the miasma
    of the tile it stands on and all surrounding tiles. This action
    takes 2 stamina.
- The end turn button will end the players current turn. This refreshes
  stamina back to 4 on all of the units. Any buildings that are currently
  warping in will be progressed if there is enough energy in the network.
  The enemy also gets to take their turn.

## Buildings

- **Conduit** - Transfers energy and connects buildings up to two tiles away.
  They are a cheap way to spread the reach of your energy network.
  A valid energy connection is shown by a light blue line connecting buildings.
- **Harvester** - Generates 8 energy per turn when built on top of an energy
  node and 1 energy per turn otherwise. Connect this to your Warp Gates via
  Conduits.
- **Purifier** - A defensive structure that clears the Miasma off of one nearby
  tile per turn. Must be connected to an energy network to function. Draws 5
  power per turn.
- **Warp Gate** - Warps in buildings and units at the expense of energy. Each
  Warp Gate can warp in one building at a time. Two Warp gates can warp in two
  buildings concurrently. Any energy generated by Harvesters is stored in the
  Warp Gate for future use.

## Miasma

A quickly spreading, unknown alien life form that destroys buildings and
kills units. It can be cleared away by using units' purify action and by
building purifiers.

## Tips and Tricks

Because units have 4 actions, they can move towards Miasma, purify, then move
back to safety each turn. However, when stationary, units can purify twice per
turn, making a significant dent in the surrounding corruption. Use this for
defensive formations only, as it places the unit at significant risk.

Drop pods are scattered around the planet, and contain more units or sensor
equipment that scans the surrounding area. Move a unit over one to open it up.

You win when you have eradicated your enemy (manually or with the burst of
energy from 6 warp gates). You lose when you have no more buildings or units
left. You can only win or lose at the end of a turn.

