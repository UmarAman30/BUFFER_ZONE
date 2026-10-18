# BUFFER ZONE

**CIVIL GAME JAM 2026** · Theme: *Disaster preparedness and awareness*

You are the night operator at the Kiranchi Emergency Operations Center. Disasters break out across five districts while a live feed fills with sensor readings, emergency calls, radio reports and social media posts, and some of those posts are false. Read the feed, check each district's risks, and send the right team before public trust collapses. Survive the 10-minute shift.

The game's point is awareness: good dispatching comes from reading the signals, trusting official sources over rumors, and acting early. At the end of the shift, a report card shows how many rumors you ignored and how many reports you read before dispatching.

Available in **English and Turkish** (switch on the main menu, or in the pause menu under CONTROLS).

---

## How to run

**Windows build (submitted ZIP)**
1. Unzip the ZIP.
2. Run `BufferZone.exe`. Nothing needs installing.
3. The game opens fullscreen. Press **F11** (or Alt+Enter) to switch between fullscreen and windowed.

Requirements: Windows 10/11 (64-bit), a graphics card with OpenGL 3.3 support.

**From source**
1. Install [Godot 4.7.2](https://godotengine.org/download) (standard build).
2. Open Godot, choose *Import*, and select `project.godot` in this folder.
3. Press **F5** to play. To export, use *Project → Export → Windows Desktop* (Godot 4.7.2 export templates required).

---

## How to play

- **Goal:** keep the PUBLIC TRUST bar above zero until the clock reaches 10:00.
- **Alerts** appear on the map and turn green → yellow → red as time passes. The earlier you answer, the more trust you gain. A red alert left alone runs out and costs trust.
- **Read the live feed** before you send anyone: reports often arrive before the alert does. Single social posts can be rumors; official sensor and radio reports are reliable.
- **Send the right team:**
  - Rapid Response: wildfires, riots, crashes, evacuations
  - Heavy Rescue: earthquakes, landslides, floods, storms, eruptions
  - Hazmat & Grid: chemical leaks, reactor trouble, power surges
- The wrong team gets stuck and costs trust; a "close" team works slowly for half the reward.
- At minute 4 a **missile event** starts: decode the override cipher before impact.

### Controls

| Input | Action |
|---|---|
| Left-click | Select alerts, teams and buttons |
| Right-click | Open / close the live feed |
| 1, 2, 3 | Pick a team, then click an alert |
| Drag a team card onto an alert | Dispatch |
| Shift + left-click a district | Show its landmarks and risks |
| 0–9 / keypad | Enter the cipher code during the missile event |
| Esc | Pause menu (resume, controls, restart, main menu) |
| F11 / Alt+Enter | Toggle fullscreen |

---

## Project structure

```
assets/    audio, fonts, images (map, portraits, team icons, icon), shaders
data/      config/ (balance and map data), en/ (English text), tr/ (Turkish text + UI strings)
scenes/    title_screen, intro_terminal, main, crt_overlay
scripts/   autoload/ (core systems), models/, scenes/ (one per scene), ui/
```

---

## Team

- **Umar Aman**: Developer
- **Rida Muneeb**: Developer
- **Ali Imran**: Developer
- **Wamiq Haider**: Developer; character drawings, team icons and the original city map

---

## Third-party assets and licenses

| Asset | Author | License | Link |
|---|---|---|---|
| "Dark Ambience Loop" (music) | Iwan Gabovitch | CC-BY 3.0 | https://opengameart.org/content/dark-ambience-loop |
| Ultimate UI SFX Pack | JDSherbert | Author's royalty-free license (credit required, no redistribution) | https://jdsherbert.itch.io/ultimate-ui-sfx-pack |
| 400 Sounds Pack | Chequered Ink | Royalty-free (credit optional; unaltered files may not be redistributed) | https://ci.itch.io/400-sounds-pack |
| UI Buttons Sound Effects Pack + Glitches | pknm | CC BY 4.0 | https://pknm.itch.io/ui-buttons-sound-effects-pack |
| Sound recordings | Joseph Sardin (BigSoundBank) | CC0 | https://bigsoundbank.com |
| Realistic CRT shader | c64cosmin (with pend00, Timothy Lottes, ahopness) | CC0 | https://godotshaders.com/shader/realistic-crt-shader/ |
| Home Video font | GGBotNet | CC0 | https://ggbot.itch.io/home-video-font |
| VT323 font | Peter Hull | SIL OFL 1.1 | https://fonts.google.com/specimen/VT323 |
| Godot Engine 4.7.2 | Juan Linietsky, Ariel Manzur and contributors | MIT | https://godotengine.org/license |

All sounds and music were trimmed, looped, converted and/or normalised for the game. Full credits are in the game (CREDITS.EXE on the main menu).

### Files not in this repo

- **JDSherbert sounds:** `assets/audio/ui_click.wav`, `feed_open.wav`, `screen_switch.wav`, `feed_close.wav`, `feed_ping.wav`. The pack's license forbids redistributing the files, so they are left out. To restore them, download the pack from the link above, then trim and export the matching UI sounds to those file names (44.1 kHz mono WAV). The game runs without them; those UI sounds are just silent.
- **Raw downloads** (`assets/audio_src/`): original, unedited source files, not needed to run the game.

---

## AI usage

- **Code:** Claude (Anthropic) was used as a coding assistant throughout development. The team designed the game and its mechanics and directed and reviewed every feature.
- **Text:** Claude helped generate the in-game text (feed reports, briefing, interface) and produced the Turkish translation.
- **Visuals:** the city map was hand-drawn by Wamiq Haider, with overlays and animation added with Claude. Character portraits, team icons and the logo were hand-drawn by Wamiq Haider and cleaned up (blur removal, pixel-grid snapping) by a Claude-written script.
- **Sound:** six effects (ambient hum, radio squelch, missile whistle and impact, intercept launch and hit) were synthesized by Claude-written code.

Full details are in the jam submission's AI declaration.
