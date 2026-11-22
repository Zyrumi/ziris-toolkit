# Ziri's Toolkit

Small helpers for World of Warcraft: Forever in one addon. Each part can be switched on or off: click Ziri's face on the edge of the minimap, type `/zt`, or go to Esc > Options > AddOns > Ziri's Toolkit. Drag the minimap button to move it; it can be hidden on the settings page.

## The parts

**Loot Highlight.** Points out nearby herbs, ore, chests, quest objects and corpses with loot. It has its own settings page under Ziri's Toolkit, and `/lh` still works. It changes a few of the game's own settings while you play and puts yours back every time you log out, so nothing stays changed if you remove the addon.

**Fresh Ranks.** When you learn a higher rank of a spell, your action buttons with the old rank get the new one. Lower ranks you placed on purpose stay. New spells go into an empty slot.

**Cleanse buttons.** A small button with your cleanse spell's icon beside your own frame and each party member's frame. Click it to cast your cleanse spell on that person, no targeting needed.

| Class | Left click | Right click |
|---|---|---|
| Paladin | Purify, then Cleanse from level 42 | |
| Druid | Remove Curse | Abolish Poison (or Cure Poison) |
| Shaman | Cure Poison | Cure Disease |
| Mage | Remove Lesser Curse | |
| Priest | Dispel Magic | Abolish Disease (or Cure Disease) |

- Out of combat, a button lights up with a colored frame and a letter for the debuff type (M magic, C curse, P poison, D disease) when that person has something you can remove. With nothing to remove it is dimmed.
- In combat the game hides people's debuffs from addons, so the button stays plain. Clicking still works: if there is nothing to remove, the game just says so.
- Hover a button to see which click does what.
- The buttons sit on the right of the game's frames and move with them (Edit Mode). Classic and raid-style party frames both work.
- Classes without a cleanse spell don't get buttons.

**Thanks.** Does the /thank emote at a player who gives you a buff out in the world.

- Party and raid members are never thanked.
- Each person at most once a minute, and several buffs at once get one thank you.
- Short buffs (like a proc from someone's heal) and buffs during combat are skipped.
- `/zt thanks` lists the last buffs from others and why each was or wasn't thanked.

**Undress.** A button on the top edge of your character window (C), at the right end. For corpse runs, when you might die again and again: gear in your bags loses no durability.

- **Undress** puts every equipped item that can lose durability into your bags. Rings, necklace, trinkets, shirt and tabard stay on.
- **Dress** puts exactly those items back in their slots. It remembers them even after you log out.
- It always takes off what you wear right now, so there is no equipment set to keep up to date.
- If your bags are full, what doesn't fit stays on, and chat tells you how many.
- Gear can't be changed in combat or while you are dead. Undress before the run, dress when you are through.

**Boat times.** A few lines at the top of the screen, only when they matter:

- Standing at a dock: when each boat or zeppelin from there leaves, for example "Boat to Menethil leaves in 1:42". If it is still on its way, also when it arrives.
- On board: "Arriving at Auberdine in 0:51".
- A "~" in front means the time is an estimate that hasn't been confirmed recently.
- The times come from the DockWatch addon, which learns them and shares them between players. Keep DockWatch installed; you can switch off its own map, window and voices in its options (`/dw options`).

**Tidy friends list.** Battle.net friends who are online somewhere you can't join them move to the bottom of your friends list, below your offline friends. Nobody is removed.

- "Can't join them" is the game's own check, the one that greys out the invite button: another rule set, another WoW version, another game or only the Battle.net app.
- Favorites always stay on top, and offline friends stay where they are.
- `/zt friends` lists your online friends and says why each one stays or moved.

**Instance limit.** The game lets an account enter at most 5 new dungeon or raid instances an hour and 30 a day. This counts the ones you enter, on all your characters.

- Each time you enter a new instance, chat says which number it was: "Deadmines counted: 3 of 5 this hour, 8 of 30 today."
- While you are at a limit, a line at the top of the screen counts down until the next instance is allowed.
- Going back into the same instance doesn't count again. Going into a fresh copy after a reset does.
- `/zt instances` lists the instances of the last day.
- The game doesn't tell addons your count, so instances entered without the toolkit running (for example on another computer) are missing.

**Rested XP per character.** `/zt rested` lists your characters, most rested first, with how much of a level each has rested and when they will be full.

- It remembers each character when you play them and works out how much more they have rested since: 5% of a level every 8 hours in an inn or city, a quarter of that elsewhere, up to one and a half levels.
- Log in on each character once to add it. Characters at max level are left out.

**Buff reminders.** Out of combat, an icon for each of your own buffs, auras and tracking that is missing (after dying, or when it ran out) or about to run out. Click the icon to cast it on yourself. Nothing shows when all is well.

- Covers what your class can cast on itself: priest Fortitude, Inner Fire, Divine Spirit and Shadow Protection, mage Arcane Intellect and armors, druid Mark of the Wild, Omen of Clarity and Thorns, shaman shields, warlock armors, hunter aspects and Trueshot Aura, and gathering tracking (Find Minerals, Find Herbs, Find Fish, Find Treasure). Creature tracking like Track Beasts is never asked for, since it fills up the minimap.
- Paladin blessings, auras and Righteous Fury are no longer here: they live in the separate addon Zyrumi's Libram, which also blesses your whole group with one key.
- Pick which ones per character on the Buff reminders page under Ziri's Toolkit. Thorns and Shadow Protection start switched off.
- Groups like hunter aspects or mage armors are fine with any one of them; a click casts the one you had last. Tracking is switched back on through the minimap.
- "About to run out" means the last tenth of the buff: at least 30 seconds and at most 5 minutes before it ends.
- Hidden in combat, while dead, on a flight path and (druids, shamans) while shapeshifted. Shift-drag an icon to move the row. `/zt buffs` lists what is watched and how each stands.

**Flight timer.** While you are on a flight path, a bar at the top of the screen shows where you are going, how long is left and how far along you are.

- Hover a destination on the flight master's map to see how long the flight takes.
- Times come from the flights you take yourself (each route you fly all the way is remembered on all your characters) and, for routes you haven't flown, from flight times shared by the InFlight and FlightCountdown addons. Neither needs to be installed.
- A time with "about" in front is the stops along the way added up, or worked out from the route's length. A route nobody has timed counts up instead and is remembered when you land.
- Flights you leave early are not saved. `/zt flights` lists the routes learned so far.

**Threat for tanks.** In combat, small icons so you can see at a glance which mobs in a pack are yours:

- Green shield: yours. Half shield: yours, but someone is about to take it. Red warning with a name beside it: on someone else, and who.
- One sits above the name on each enemy nameplate (needs enemy nameplates on, V), and one above your target's name bar, where the game's own threat percentage would be. Hover that one for the numbers: how far ahead of the next person you are, or your share of the holder's threat.
- Solo, a mob on you is no news, so nothing shows then.
- Bosses: the game hides their threat numbers from addons; the icons still work.
- When you are not the tank (no tank role, form, stance or Righteous Fury), the warning marks mobs that are on you in a group, and the half shield shows on your target when you are close to pulling it.

**Healer mana after combat.** When a fight ends and you are tanking in a group, a warning in the middle of the screen if a healer is under 20% mana, for example "Healer low on mana: Holly 14%". Time to wait before the next pull.

- Only people with the healer group role count; nobody is guessed from their class.
- Tanking means a tank role, a tanking form or stance, or Righteous Fury up.
- On Forever the game hides other players' mana from addons. Then the game draws the warning itself, one line per healer that only shows when they are under 20%, and the addon never learns the number.
- `/zt healers` shows what it sees right now: whether you count as a tank and each person's role, plus each healer's mana on screen for a few seconds.

**Disconnect tracker.** In a group, chat says when someone disconnects ("Misty disconnected.") and when they are back ("Misty is back (gone 2:14)."). While anyone is offline, a line at the top of the screen counts up: "Misty disconnected 1:23 ago".

- Someone who was already offline when you joined the group or reloaded shows as "offline" without a time: the game doesn't say since when.
- People who leave the group are dropped from the list.

**Photo mode.** The game's Toggle UI key (Alt+Z unless you changed it) hides the interface but leaves names floating over everyone's heads. With photo mode on, the same key also hides names over players, NPCs and pets (your own too), nameplates, chat bubbles and the damage and healing numbers over targets. Press it again and everything is back exactly as you had it.

- Pick what goes on the Photo mode page under Ziri's Toolkit. There is also a camera option, off at first, that slowly circles your character while the interface is hidden.
- Nameplates can't be changed during a fight, so in combat they go (or come back) as soon as the fight ends.
- If the game closes while the interface is hidden, your settings go back at the next login.
- `/zt photo` lists the settings it changes and their values right now, and what happened the last time you hid the interface (anything that stayed on).

**AFK screen.** When you go AFK (`/afk`, or after a few minutes without doing anything), the interface hides, names, nameplates, chat bubbles and damage numbers go as in photo mode, the camera slowly circles your character, and a bar along the bottom of the screen shows your character in 3D, your name, level, race and class, your guild, how long you have been away and the time.

- Moving, casting or chatting ends AFK and brings everything back, and so does the Toggle UI key. A fight ends it at once.
- It has its own switch on the main page and works whether photo mode is on or not. Photo mode's page has a switch to show the same bars when you press the Toggle UI key yourself; then they show where you are instead of the away timer.
- Its look is set on the AFK screen page under Ziri's Toolkit: one bar along the bottom or a bar at the top and the bottom; whether your character shows, and sliders for where it stands across the screen (X), how high (Y), which way it faces all the way round (Z) and how big it is; what it does, picked from a list of about a hundred animations (emotes, sitting and lying poses, things townsfolk do like leaning on a wall, and professions), with only the ones your character's model has on offer; the game's logo, your class crest, a round class medallion or your Alliance or Horde crest in the middle; and a crest by your name. Type `/afk` to see it.
- In dungeons and raids the game may not tell addons that you are AFK; then the AFK screen doesn't come up.
- `/zt afk` shows which logo, class icon and faction picture the game gives the AFK screen, and whether your character's model has the lean animations.

**Console settings.** A page under Ziri's Toolkit with sliders and switches for game settings you would otherwise type with `/console`: max camera distance (past the 2.0 the game's Options allow), grass and foliage amount and distance, weather, screen glow, grey screen when dead, spell queue window, nameplate distance, always compare items, shorter loading screens and screenshot quality.

- These are the game's own settings. The page changes them directly and keeps no copy, so they stay as you set them even without the toolkit. "Reset to game defaults" puts them all back.
- Settings your game version doesn't have are left off the page. If the game rounds or limits a value, the slider shows what the game kept.
- The game's Ground Clutter graphics option sets the grass and foliage values again when you change it.

## Coming from Loot Highlight or Fresh Ranks

This addon replaces the separate Loot Highlight and Fresh Ranks addons. While an old one is still installed, the toolkit leaves that part to it and says so in chat once. Remove the old folder to use the toolkit's. Your Loot Highlight settings move over by themselves after you have played once with both installed.

## Thanks

Flight times for routes you haven't flown come from [InFlight](https://github.com/LudiusMaximus/InFlight) (TotalPackage, Deranjata, LudiusMaximus) and [FlightCountdown](https://github.com/burk3/FlightCountdown) (burk3), both under the MIT License; see FlightData.lua.

The animation numbers in AnimData.lua come from the community list at [wowdev.wiki](https://wowdev.wiki/M2/AnimationList).

The class crests on the AFK screen (Media/Crests) are Blizzard's class crest art from the WoW blog, as kept on the [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Class). The art belongs to Blizzard Entertainment.

## Install

Copy the `ZirisToolkit` folder into `World of Warcraft\_forever_\Interface\AddOns`, or tick it in Ziri's Workshop.
