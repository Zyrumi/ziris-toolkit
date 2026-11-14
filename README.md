# Ziri's Toolkit

Small helpers for World of Warcraft: Forever in one addon. Each part can be switched on or off: type `/zt`, or go to Esc > Options > AddOns > Ziri's Toolkit.

## The parts

**Loot Highlight.** Points out nearby herbs, ore, chests, quest objects and corpses with loot. It has its own settings page under Ziri's Toolkit, and `/lh` still works.

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

- Covers what your class can cast on itself: paladin auras, blessings and Righteous Fury, priest Fortitude, Inner Fire, Divine Spirit and Shadow Protection, mage Arcane Intellect and armors, druid Mark of the Wild, Omen of Clarity and Thorns, shaman shields, warlock armors, hunter aspects and Trueshot Aura, and tracking (Find Minerals, Find Herbs and the rest).
- Pick which ones per character on the Buff reminders page under Ziri's Toolkit. Righteous Fury, Thorns and Shadow Protection start switched off.
- Groups like paladin auras or hunter aspects are fine with any one of them; a click casts the one you had last. Tracking is switched back on through the minimap.
- "About to run out" means the last tenth of the buff: at least 30 seconds and at most 5 minutes before it ends.
- Hidden in combat, while dead, on a flight path and (druids, shamans) while shapeshifted. Shift-drag an icon to move the row. `/zt buffs` lists what is watched and how each stands.

## Coming from Loot Highlight or Fresh Ranks

This addon replaces the separate Loot Highlight and Fresh Ranks addons. While an old one is still installed, the toolkit leaves that part to it and says so in chat once. Remove the old folder to use the toolkit's. Your Loot Highlight settings move over by themselves after you have played once with both installed.

## Install

Copy the `ZirisToolkit` folder into `World of Warcraft\_forever_\Interface\AddOns`, or tick it in Ziri's Workshop.
