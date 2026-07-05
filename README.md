# GuusRaidBuilder

GuusRaidBuilder is a World of Warcraft addon for building raid presets and executing them through `.z addinvite` and `.z addlegacy` commands.

It is built for a vanilla-style client and is aimed at setups where raid members are spawned or invited through custom server commands rather than the normal Blizzard raid tools.

## Features

- Create and rename raid presets.
- Store per-account bot setups with class, role, spec, race, gender, and tier.
- Assign legacy characters to accounts.
- Reorder raid members with a visible `SpawnOrder` column.
- Start execution from a chosen visible spawn-order row.
- Export and import presets as text.
- Open the addon from a minimap icon or slash command.

## Requirements

- WoW client interface `11403`.
- Server or environment that supports:
  - `.z addinvite`
  - `.z addlegacy`
  - `.z transfer`

## Installation

1. Download or clone this repository.
2. Place the `GuusRaidBuilder` folder inside your `Interface/AddOns` directory.
3. Make sure the bundled `libs` folder is included.
4. Start the game and enable the addon on the character selection screen if needed.

Example folder layout:

```text
Interface/
  AddOns/
    GuusRaidBuilder/
      GuusRaidBuilder.toc
      GuusRaidBuilder.lua
      libs/
```

## Opening The Addon

- Type `/grb`
- Or type `/raidbuilder`
- Or click the minimap launcher icon

## Basic Workflow

1. Open the addon.
2. Create a preset with `New`.
3. Add your level 60 accounts on the left side.
4. Add bot slots for those accounts on the right side.
5. Adjust class, role, spec, race, gender, tier, and spawn order.
6. Optionally assign legacy characters with the `L` button.
7. Set `Spawn #` if you want execution to begin later in the visible spawn order.
8. Press `Execute Raid`.

## Spawn Order

`Spawn #` follows the visible `SpawnOrder` column in the UI.

- Your own row is part of the visible order and can be moved up or down.
- If `Spawn #` points at your own row, execution skips it and continues with the next inviteable row.
- If `Spawn #` is higher than the number of visible rows in the preset, nothing is executed and the addon prints an error message in chat.

## Export And Import

The addon can export presets as text blocks and import them again later.

This is useful for:

- backing up presets
- moving presets between installs
- sharing presets with other users of the addon

Use the `Export` button to copy a preset and the `Import` button to paste one back in.

## Notes

- Presets are stored in the `GuusRaidBuilder_Config` saved variable.
- The addon includes its required libraries in the repository.
- A clean install should include the full addon folder, including `libs`.

## Repository

GitHub: https://github.com/Guus567/GuusRaidBuilder