# Ziri's Toolkit

Small helpers for World of Warcraft: Forever in one addon. Each part can be switched on or off: type `/zt`, or go to Esc > Options > AddOns > Ziri's Toolkit.

## The parts

**Loot Highlight.** Points out nearby herbs, ore, chests, quest objects and corpses with loot. It has its own settings page under Ziri's Toolkit, and `/lh` still works.

**Fresh Ranks.** When you learn a higher rank of a spell, your action buttons with the old rank get the new one. Lower ranks you placed on purpose stay. New spells go into an empty slot.

**Cleanse buttons.** A small list with you and your party members. Click a name to cast your cleanse spell on that person, no targeting needed.

| Class | Left click | Right click |
|---|---|---|
| Paladin | Purify, then Cleanse from level 42 | |
| Druid | Remove Curse | Abolish Poison (or Cure Poison) |
| Shaman | Cure Poison | Cure Disease |
| Mage | Remove Lesser Curse | |
| Priest | Dispel Magic | Abolish Disease (or Cure Disease) |

- Out of combat, a name gets a colored frame and the debuff type (for example "Curse") when it has something you can remove.
- In combat the game hides people's debuffs from addons, so the frame may not show. Clicking still works: if there is nothing to remove, the game just says so.
- Hover a name to see which click does what.
- Drag the "Cleanse" title to move the list. You can lock it in the settings.
- Classes without a cleanse spell don't see the list.

**Thanks.** Does the /thank emote at a player who gives you a buff out in the world.

- Party and raid members are never thanked.
- Each person at most once a minute, and several buffs at once get one thank you.
- Short buffs (like a proc from someone's heal) and buffs during combat are skipped.

## Coming from Loot Highlight or Fresh Ranks

This addon replaces the separate Loot Highlight and Fresh Ranks addons. While an old one is still installed, the toolkit leaves that part to it and says so in chat once. Remove the old folder to use the toolkit's. Your Loot Highlight settings move over by themselves after you have played once with both installed.

## Install

Copy the `ZirisToolkit` folder into `World of Warcraft\_forever_\Interface\AddOns`, or tick it in Ziri's Workshop.
