# pfUI-TotemBar

A [pfUI](https://github.com/brues-code/pfUI) third-party module for shamans (WoW 1.12 / OctoWoW).

## Features
- One button per element (Earth, Fire, Water, Air) showing your **active** totem.
- **Left-click** an element button: cast its active totem. **Right-click**: pin the totem list open.
- Hover an element button to open the list of every totem you know for that element:
  - **Left-click** a totem: cast it.
  - **Right-click** a totem: make it the active totem of that element.
- Choose the active totem of each element from a dropdown in the pfUI config
  (`/pfui` → Thirdparty → Totem Bar). Each list also has **None** (red cross): nothing is cast
  for that element.
- Cooldown swipe, out-of-mana tint ([Nampower](https://github.com/brues-code/nampower)) and remaining time of the totem currently down.
- Movable with pfUI's unlock mode; size, spacing, bar direction and list direction are configurable.
- Always casts the highest rank you know. Totems are detected by icon (locale independent), and
  with [Nampower](https://github.com/brues-code/nampower) also by spell effect, so custom server totems show up too.

## Secondary totem
For totems with a cooldown, **middle-click** another totem of the same element in the button's
list to make it the secondary (middle-click it again to remove it). While the primary is on
cooldown (the 1.5s global cooldown is ignored) the button and every command cast the secondary;
as soon as the primary is ready it is cast again. Commands do nothing while the primary (or the
secondary, during the cooldown) is still active; a left-click on the button always casts. The
button shows the totem that will be cast, a small corner icon shows the secondary (outlined when
it is the one cast) and the cooldown wheel stays on the primary. Saved in the pfUI config.

## Cast every active totem from one macro
```
/totembar all
```
Casts each active totem in order, exactly like a macro with one `/cast` line per totem.

By default it only refreshes what is missing: a totem that is still up is skipped, unless it is
about to expire (configurable threshold) or, with the **[UnitXP_SP3](https://github.com/brues-code/UnitXP_SP3)** DLL, you are out of its range.
The range of each totem is read from its tooltip ("within X yards"); the bar timer turns red when
you are out of range. Your totems are recognised (ClassicAPI UnitOwnerGUID / UnitCreatedBySpell) when
they pulse their spell or their aura lands on you (Nampower `SPELL_GO_OTHER` / `AURA_CAST_ON_SELF`),
or when they appear on target, mouseover or a nameplate.
`/totembar debug` prints what is tracked.

Options (config → Cast All): which elements are included, the order (`earth,fire,water,air`),
skip-still-active, the remaining-time threshold and the range check.

Key bindings are also available under *Key Bindings → pfUI Totem Bar*.

## Shield
Pick your shield (Lightning / Water / Earth Shield) in the config or from the shield button's list.
`/totembar shield` casts it on yourself only when it is gone, or when its charges are at or below
the "Refresh at X charges" threshold (0 = only when gone). The button shows the remaining charges.
It can also be included in `/totembar all`.

## Weapon enchant
Pick Rockbiter / Flametongue / Frostbrand / Windfury Weapon in the config or from the weapon
button's list. `/totembar weapon` casts it only when your main hand has no enchant, a different
one, or less than the "Refresh at X minutes" threshold left (0 = only when gone). With Nampower
the enchant on the weapon is recognised exactly; without it any main hand enchant counts.
The button shows the time left. It can also be included in `/totembar all`.

## Totem item swap
The totem items you carry (equipped in the relic slot or in your bags) are listed in the
"Totem Item" dropdown and on the totem item button. `/totembar relic` (or `/totembar item`)
equips the active one if it isn't already equipped. Librams, idols and other items are ignored.

## Turning features off
Shield, weapon enchant and totem item swap each have an **Enable** checkbox in the config.
Disabled, the button is hidden, its command does nothing and it is left out of `/totembar all`.

## Commands
| Command | Effect |
| --- | --- |
| `/totembar all` | cast every active totem |
| `/totembar earth\|fire\|water\|air` | cast the active totem of that element, if it needs a refresh |
| `/totembar totems` | cast the 4 active totems that need a refresh, never the shield (`force` = all 4) |
| `/totembar weapon` | cast the active weapon enchant, if it is gone or about to expire |
| `/totembar relic` (or `item`) | equip the active totem item |
| `/totembar shield` | cast the active shield, if it is gone or low on charges |
| `/totembar <element\|shield> force` | cast it even if it is still up |
| `/totembar next\|prev <element>` | cycle the active totem of an element |
| `/totembar set <element> <name\|none>` | e.g. `/totembar set air windfury` |
| `/totembar list` | print the active totems |
| `/totembar scan` | rescan the spellbook |

`/ptb` is a short alias. For scripts: `pfTotemBar.CastAll()`, `pfTotemBar.Cast("fire")`,
`pfTotemBar.CastTotems()`, `pfTotemBar.CastShield()`, `pfTotemBar.CastWeapon()`, `pfTotemBar.EquipRelic()`, `pfTotemBar.SetActive("water", "mana spring")`.

## Install
Copy the `pfUI-TotemBar` folder into `Interface\AddOns`. Requires [pfUI](https://github.com/brues-code/pfUI).
