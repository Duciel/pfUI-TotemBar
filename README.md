# pfUI-TotemBar

A [pfUI](https://github.com/shagu/pfUI) third-party module for shamans (WoW 1.12 / OctoWoW).

## Features
- One button per element (Earth, Fire, Water, Air) showing your **active** totem.
- **Left-click** an element button: cast its active totem. **Right-click**: pin the totem list open.
- Hover an element button to open the list of every totem you know for that element:
  - **Left-click** a totem: cast it.
  - **Right-click** a totem: make it the active totem of that element.
- Choose the active totem of each element from a dropdown in the pfUI config
  (`/pfui` → Thirdparty → Totem Bar).
- Cooldown swipe, out-of-mana tint (Nampower) and remaining time of the totem currently down.
- Movable with pfUI's unlock mode; size, spacing, bar direction and list direction are configurable.
- Always casts the highest rank you know. Totems are detected by icon (locale independent), and
  with Nampower also by spell effect, so custom server totems show up too.

## Cast every active totem from one macro
```
/totembar all
```
With **Nampower** the totems are fed into its spell queue one after the other, so a single press
drops all of them back to back (Nampower can only hold one GCD spell at a time, the addon queues
the next totem each time the previous one goes off). Without Nampower each press casts the next
totem of the list instead.

Options (config → Cast All): which elements are included, the order (`earth,fire,water,air`),
and "Skip totems that are still active" (with a remaining-time threshold).

Key bindings are also available under *Key Bindings → pfUI Totem Bar*.

## Commands
| Command | Effect |
| --- | --- |
| `/totembar all` | cast every active totem |
| `/totembar earth\|fire\|water\|air` | cast the active totem of that element |
| `/totembar next\|prev <element>` | cycle the active totem of an element |
| `/totembar set <element> <name>` | e.g. `/totembar set air windfury` |
| `/totembar list` | print the active totems |
| `/totembar scan` | rescan the spellbook |

`/ptb` is a short alias. For scripts: `pfTotemBar.CastAll()`, `pfTotemBar.Cast("fire")`,
`pfTotemBar.SetActive("water", "mana spring")`.

## Install
Copy the `pfUI-TotemBar` folder into `Interface\AddOns`. Requires pfUI.
