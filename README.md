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
- The buttons sit on the left of the game's frames and move with them (Edit Mode). Classic and raid-style party frames both work.
- Classes without a cleanse spell don't get buttons.

**Thanks.** Does the /thank emote at a player who gives you a buff out in the world.

- Party and raid members are never thanked.
- Each person at most once a minute, and several buffs at once get one thank you.
- Short buffs (like a proc from someone's heal) and buffs during combat are skipped.

## Coming from Loot Highlight or Fresh Ranks

This addon replaces the separate Loot Highlight and Fresh Ranks addons. While an old one is still installed, the toolkit leaves that part to it and says so in chat once. Remove the old folder to use the toolkit's. Your Loot Highlight settings move over by themselves after you have played once with both installed.

## Install

Copy the `ZirisToolkit` folder into `World of Warcraft\_forever_\Interface\AddOns`, or tick it in Ziri's Workshop.
