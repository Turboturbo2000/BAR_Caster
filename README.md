# BAR Caster Widget

A spectator and replay analysis widget for [Beyond All Reason](https://www.beyondallreason.info/).

Designed for casters, tournament observers, and anyone who wants deeper insight while watching BAR games.

![License](https://img.shields.io/github/license/Turboturbo2000/BAR_Caster)

## Features

- **Player Ranking** — sortable by metal/s, army value, mex count, trade balance, or reclaim
- **Team Balance Bar** — weighted eco + army comparison between teams
- **Team Eco Graph** — Team 1 vs Team 2 metal income over time
- **Eco Comparison Graph** — top 4 players metal/s as overlapping line chart
- **Territory Control** — mini heatmap showing which team controls which area
- **Army Composition** — stacked bar chart tracking raider/assault/skirmisher/air mix over time
- **Trade Balance** — kills vs losses per player (who trades best?)
- **Reclaim Estimation** — per-player reclaim income tracking
- **Idle Army Warning** — highlights players with high % of idle combat units
- **T2 Race** — tracks who reaches T2 first with timestamps
- **Battle Detection** — detects large engagements and marks them on the map
- **Alert System** — energy stall, metal overflow, battles, overrun warnings
- **Event Timeline** — horizontal bar with colored event markers and time ticks
- **Commentator Mode** — auto-switches camera to the most exciting player
- **MVP Display** — top killer, best trade, peak eco, first T2 at game end
- **OBS Export** — writes game data to infolog.txt for external overlay tools
- **FlowUI Support** — uses BAR's native rounded UI style when available
- **Team Colors** — player names shown in their actual in-game colors

## Installation

### Option 1: Manual copy

1. Copy `gui_caster_widget.lua` to your BAR widgets folder:
   ```
   C:\Program Files\Beyond-All-Reason\data\LuaUI\Widgets\
   ```
2. Copy the `caster_modules/` folder to the same location:
   ```
   C:\Program Files\Beyond-All-Reason\data\LuaUI\Widgets\caster_modules\
   ```

### Option 2: deploy.bat (Windows)

Run `deploy.bat` — it copies everything to the right place.

## Usage

1. Start BAR and spectate a game or watch a replay
2. The widget activates automatically in spectator mode
3. Press **F11** and enable **"BAR Caster Widget"** if it's not already active

### Controls

| Key / Command | Action |
|---------------|--------|
| **F9** | Toggle panel visibility |
| **PageUp / PageDown** | Switch watched player |
| **/castersort** | Cycle sort mode (metal, army, mex, trade, reclaim) |
| **/castercast** | Toggle commentator mode (auto-switch to most exciting player) |
| **/casterobs** | Toggle OBS export |

The panel can be dragged by clicking and holding the title bar.

## OBS Overlay

For streaming, an optional Python script reads game data from `infolog.txt` and writes it to a text file that OBS can display:

```bash
python caster_obs_overlay.py
```

Then in OBS: add a **Text (GDI+)** source, enable "Read from file", and point it to:
```
C:\Program Files\Beyond-All-Reason\data\caster_obs.txt
```

## Project Structure

```
BAR_Caster/
├── gui_caster_widget.lua          Main widget
├── caster_modules/
│   ├── rendering.lua              Rendering helpers (FlowUI + fallback)
│   ├── unit_classify.lua          Unit classification (mex, factory, roles...)
│   └── unit_helpers.lua           Commander/builder/idle detection
├── caster_obs_overlay.py          OBS integration script
├── deploy.bat                     Windows deploy script
└── LICENSE                        GPL-3.0
```

## Requirements

- [Beyond All Reason](https://www.beyondallreason.info/) (any recent version)
- Spectator or replay mode
- Python 3 (only needed for OBS overlay)

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.
