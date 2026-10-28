Contains a host of changes over the original HUDLocator (https://github.com/Srlimao/Palword-mods/blob/master/HUDLocator/), including:

New features:
* Light beam beacons (using the same color as radar text, text and beacons can be individually turned on/off for each type)
* Show unactivated fast travel points and hacking terminals on the radar
* Track completion of hacking terminals and journals
* Filtered loot table to show only loot you are interested in (for example skill fruits and lotus flowers)

Fixes/Improvements:

Completion tracker
* Fixed completion tracker that now tracks your region exactly (via hand drawn region boundaries) and tracks objects within those regions accurately, instead of guessing based on the total. Regions can be modified should there be a need in the future with the built in boundary tool by pressing Alt+F6 on the map screen, but this is more of a developer tool, not meant for end users, and can easily be disabled in released versions via a flag.
* Completion builds its entire list of collectibles from map data. Alphas and bounties from their spawners. Effigies, journals, fast travel, hack terminals and watchtowers from their loaded actors.
* Effigies include every effigy type, not just Lifmunk.
* Some other collectibles/objectives that were previously omitted are now counted.
* Oil rigs are counted, and tracked as their own region.
* Outer isles are tracked as their own region.
* The position of the completion tracker actually persists between restarts.
* You can now recolor the completion tracker like everything else, for example to change the opacity, because that was bugging me.
* Completion tracker hides while you are in a base or in a cutscene (the latter needs more testing to ensure it works in every case, because I've had problems accurately detecting when a cutscene is playing)

Misc
* Player controller lookup is cached for better performance.
* Menu has been reworked, as all the new features were making it too crowded.
* Unique text/beacon color for convenient Mimog tracking (because they're fun to hunt down)
* Shiny pals no longer also show as Boss
* Other minor improvements
