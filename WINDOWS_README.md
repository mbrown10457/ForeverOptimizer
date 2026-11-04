# ForeverOptimizer on Windows

One command installs everything. It finds your World of Warcraft: Forever folder, downloads the
latest ForeverOptimizer release and the QuestieDB quest database, and copies both into
`Interface\AddOns`. Run the same command again later to update.

## Install

1. Install World of Warcraft: Forever through Battle.net first (it only needs to be installed, not launched).
2. Open PowerShell: press the Windows key, type `PowerShell`, press Enter.
3. Paste this line and press Enter:

```powershell
irm https://raw.githubusercontent.com/mbrown10457/ForeverOptimizer/main/scripts/install-windows.ps1 | iex
```

It prints what it is doing and ends with `Done.` The whole thing takes under a minute.

If you would rather start it from the Run box (Windows key + R) or from Command Prompt, use this form instead:

```
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/mbrown10457/ForeverOptimizer/main/scripts/install-windows.ps1 | iex"
```

## Check it worked

- At the character select screen, click **AddOns** (bottom left). Both **ForeverOptimizer** and **QuestieDB** should be listed and ticked. If the client says they are out of date, tick **Load out of date AddOns**.
- In the world, type `/reload`, then `/fo checklist`. The checklist walks you through the first hour.
- `/fo help` lists every command. `/fo warlock` is the warlock status line (shards, demon, mana); `/fo shaman` is the shaman one (shield, weapon imbue, totems, mana).

## If something goes wrong

- **Red text in PowerShell.** Copy the whole window and send it to Mike. The last line says what failed.
- **"Could not find the World of Warcraft: Forever folder."** The game is installed somewhere unusual. Find the folder that contains `_forever_`, then run these two lines in the same PowerShell window, with your own path:

  ```powershell
  $env:WOW_ADDONS = "D:\Games\World of Warcraft\_forever_\Interface\AddOns"
  irm https://raw.githubusercontent.com/mbrown10457/ForeverOptimizer/main/scripts/install-windows.ps1 | iex
  ```

- **Addons missing from the AddOns list in game.** Check that the two folders exist and are named exactly `ForeverOptimizer` and `QuestieDB`:

  ```
  C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\
  ```

- **Errors in game.** The addon catches its own Lua errors. Type `/fo errors` and send a screenshot, or send the saved-variables file after you log out:

  ```
  C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\<YOUR ACCOUNT>\SavedVariables\ForeverOptimizerDB.lua
  ```

## Send your data to Mike

After a session, log out (the game only writes its data on logout or `/reload`), then paste this in PowerShell:

```powershell
irm https://raw.githubusercontent.com/mbrown10457/ForeverOptimizer/main/scripts/collect.ps1 | iex
```

It puts `ForeverOptimizer-data-<date>.zip` on your Desktop. Send that file. It holds the addon's saved data and the game's General.log, nothing else.

## Remove it

Delete the `ForeverOptimizer` and `QuestieDB` folders from `Interface\AddOns`. Your recorded data stays in the `WTF` folder until you delete `ForeverOptimizerDB.lua` as well.
