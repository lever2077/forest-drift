# Forest Drift (Godot 4.3, PC + VR)

A solo drifting game on four maps, with a detailed black Nismo-style Nissan 350Z. The handling is a grippy
tarmac drift setup: weight transfer, throttle control and the handbrake all matter.

## Download and play (Windows)
1. Open the **Releases** page of this repo and download `ForestDrift-windows.zip` from the latest release.
2. Unzip it anywhere.
3. Double-click `play.bat`.

**Updates:** the start screen checks for a new release by itself. When there is one, the button under the menu
says **Update to vX.Y.Z**. Click it, and the game downloads the update, installs it and restarts. Your settings,
points and inventory are kept.

## Points, Caches, skins and Inventory
At the end of every lap, the score you earned in that lap (drifts and jumps) is multiplied by a **time bonus**
and added to your **points**. The bonus is par time ÷ your lap time, between ×0.25 and ×3. Par is the lap length
driven at 75 km/h (`PAR_SPEED` in `car.gd`). Endless Road pays out the same way every kilometre. Spend points in
**Caches** on the start screen. The **Basic Cache** costs 100 points and gives one random solid-colour car skin
(10 colours, equal odds; duplicates stack). Skins go into your **Inventory**, where **Equip** puts one on your car.
The stock gloss black is always there. Skins and caches are defined in `SKINS` and `CACHES` in
`game/scripts/profile.gd`.

**Saves:** points, skins and the equipped colour are saved in `user://profile.cfg` (on Windows
`%APPDATA%\Godot\app_userdata\Forest Drift`), next to `settings.cfg`. That folder is on each person's own
computer and is never in the download or the updates, so everyone who plays starts fresh with their own save
and updating keeps it. (v1.2-1.3 had named players; the last one played is moved back into the single save.)

## Tumbling, rollovers and roof landings
When all four wheels leave the ground, or the car tips past about 45°, it becomes a free rigid body
(`_step_rigid` in `car.gd`). It spins about its centre of mass with its own inertia (Euler's equations), so a
tumble keeps its angular momentum in the air instead of twisting. Its shell is a set of contact points: the
bumpers, wings, door sides, pillars and roof. Every point that touches the ground pushes back like crumpling
metal, which is stiff going in and barely springs back, and drags along the ground with friction. So a roof or
side landing slows, turns and settles the car by itself, and it stays on its side or roof until you press **R**.
Once three wheels are back down and it's upright, the normal driving model takes over again.
`--fliptest` runs the side, roof, slide, rollover and mid-air spin checks.

## Releasing an update (for the developer)
1. Bump `VERSION` in `game/scripts/updater.gd` (for example `1.0.0` to `1.0.1`).
2. Run `powershell -ExecutionPolicy Bypass -File tools\release.ps1`. It commits and pushes, then publishes
   GitHub release `v<VERSION>` with two files:
   - `ForestDrift-windows.zip`: the full game for new players.
   - `game-update.zip`: just the `game` folder, which the in-game updater downloads.

The updater only adds and overwrites files. A file you delete from the project stays in players' copies.

## Start screen: pick a map
The game opens on the map select screen, with a slowly turning, blurred forest behind it. No map is loaded
until you choose one. Click a map to build it and drop straight in, or press **Enter** to drive the one you
played last (marked "last played"). Press **Esc** while driving (Start on a gamepad) to come back here and
pick another map.
- **Endless Road:** a never-ending country road through the forest, generated ahead of you as you drive. It
  drives like a real road: long, slight bends (500–1400 m radius), the odd straight, and long gradual hills
  (about ±18 m over a kilometre, a few percent grade). Very occasionally, about one bend in thirty, there's a
  sharp one (60–110 m radius). The HUD shows the distance you've covered.
- **Greenwood Circuit:** a 2.5 km single-lane (10.5 m) winding forest loop with laps and three jump crests.
- **Switchback Ridge:** a 3.7 km mountain-pass circuit cut into a big open grassy hillside (`hill_track.gd`).
  Four tiers of switchback hairpins climb the slope, a ridge run crosses the top, and a long fast descent
  runs down the far side.
- **Compass Raceway:** a 2.9 km race circuit traced from a track drawing (`circuit_track.gd`). The
  start/finish is on the long bottom straight. The lap then runs round the tall left-hand loop, through the
  U-turn and the esses in the middle, up the long diagonal to the top and round the right-hand lobe. It comes
  down through the hairpin and the lower-right sweepers and back onto the straight, on gently rolling
  parkland. To change the shape, edit the `LINE` list (points in drawing pixels).

Switchback Ridge and Compass Raceway have metal guardrails along the drops and the outside of corners, and you
can hit them: the car glances off with a scrape. Street lamps line the road and switch on at night. Trees grow
in loose clumps on the open grass, with forest around the edges.

## Biomes (looks only)
Under the map list on the start screen is a **Biome** row. Every map can be dressed in any biome. The road,
the corners and the handling stay exactly the same; only the scenery around them changes. Your choice is saved.
- **Forest:** the original woodland.
- **Desert dunes:** sand ground with wind ripples, rolling dunes away from the road, a few dry scrub tufts and
  low sandstone ranges on the horizon. No trees.
- **Grasslands:** wide open plains of tall green grass with no trees at all, and low hills far off.
- **Tundra:** frozen, always-snowy ground with rocky lumps, dark stunted trees, and big snow-capped mountains
  close by.
- **Savannah:** golden grass on red earth with wide flat-topped trees.
- **Stadium:** striped, mown lawn. Grandstands full of a colourful crowd, floodlight towers and a line of
  advert boards run along both sides of the track. The boards, stands and light towers are solid, so you can
  crash into them. This biome is only for the three race tracks: Endless Road stays in the forest when it's
  picked.

Biome definitions are in `game/scripts/biome.gd`, and the stadium buildings are in `stadium.gd`. For testing,
`--biome=Desert_dunes` (spaces written as `_`) starts in a biome.

## Grass
Every map has grass (`grass.gd`): tufts of thin blades that cover the land around you and sway in the wind.
It's built to be cheap. It only appears within 50 m (34 m on Low) and thins out with distance, and it streams
in small chunks around the camera within a fixed time budget each frame. In testing it made no measurable
difference to the frame rate. Each tuft sits on the ground exactly as it's drawn, never on the road or its
gravel shoulder. The hill maps have the densest, tallest grass. Snow frosts the tips. You can set
**Grass: Off / Low / High** under Graphics in the Settings panel (F2).

## Baked lighting
**Baked lighting: Off / Low / High** (Settings > Graphics) bakes the map into a lighting field around the
camera (Godot's SDFGI) so sunlight and skylight bounce off the ground, road and trees: shade under the
canopy, green light on the car in the forest. The maps are generated when they load, so this is baked at
runtime rather than in the editor. The car and grass are lit by it but not baked into it. High adds
screen-space indirect light and costs more FPS. It's always off in VR.

## Frame rate display
The top-left of the HUD shows the frame rate and frame time: green at 60+ fps, yellow at 30–60, red below 30.
The game is single-player and offline, so there's no server to ping; the readout says so.

Tree shadows in daylight come from an invisible copy of the light tree model (about 350 triangles instead of
6,500), so the sun's shadow map no longer makes daytime much slower than night. The sound is muted whenever the
game window is in the background. `--bottest --fps` runs a timed autopilot lap with vsync off and prints the
frame rate.

## Mountains
A continuous range of snow-capped mountains lines the horizon on every map (`mountains.gd`). It sits
1.4–2.4 km out at roughly the same height all the way round, rolling gently up and down, and stays on the
horizon as you drive. The haze follows the weather: clearer on sunny days, faded in fog or snowfall. The snow
line creeps down when it snows.

## Car damage (optional)
Turn on **Car damage** under Car in the Settings panel (F2); it's saved. Under it, **Effects** decides whether
damage can also break the car mechanically (engine, wheels, suspension, axles). Turn Effects off for
looks-only damage, and the car always drives normally. Effects has its own sub-settings:
- **Engine damage:** the engine can overheat, go into limp mode and die.
- **Wheel damage:** bent wheels pull the car, axles break and steering lock is lost.
  - **Wheels fall off:** a wheel broken to 0% tears off. The tyre and rim fly away, roll along the ground and
    topple over. The bare hub drops onto the road and grinds, which slows the car and drags it round towards
    that corner. A rear wheel coming off also cuts its drive. The HUD shows that wheel as TORN OFF.

**Backspace** restarts at the start line and repairs everything, wheels included. It's a simplified take on soft-body crash physics (`car_damage.gd`):

- **Crumple frame:** a frame of 4 x 3 x 12 points runs through the car, joined by about 1,000 springy links.
  A hit pushes the shape of what you hit into it over a few frames: a tree trunk, a guardrail beam or a patch
  of ground. The links carry the push through the structure and bend for good when pushed too far. The cabin
  is stiffer than the crumple zones front and back. The body follows the frame, so the nose folds back, the
  bonnet buckles and the roof crushes in a rollover. On top of that, the metal crumples like scrunched foil,
  with sharp folds that catch the light and scuffed, scraped paint.
- **Loose parts:** the front and rear bumpers, bonnet, both doors, both mirrors and the rear wing are separate
  pieces. Hits near them, or the structure bending under them, first make them hang loose: doors swing open
  in corners, the bonnet flutters in the wind, bumpers and the wing droop off one end. Then they tear off and
  tumble along the ground. A loose bonnet rips off at high speed.
- **Mechanical damage** (only with Effects on; this one changes the handling):
  - Bent front wheels pull the car to one side, and bent rear wheels drag it round.
  - Damaged corners lose grip, and a badly bent wheel visibly leans, wobbles and shakes the car.
  - A broken suspension sags that corner.
  - A wrecked rear corner breaks that driveshaft, so you lose half the drive, or all of it with both gone.
  - A crushed front loses engine power. With a damaged radiator the engine overheats under load, goes into
    limp mode and steams; a wrecked engine dies.
  - The HUD shows engine health and temperature, each wheel and the axles.
- **Glass:** each window cracks in a spider-web from where it was hit and shatters into falling shards when hit
  hard or when its frame bends. A big frontal crash cracks the windscreen.

- **The front and engine break like the sides:** both headlights, both front wings, the radiator, the battery,
  the air box and the intake with its valve covers can all break loose. The wings hang off their back edge
  and flap open in the wind before tearing off; the rest pops out of a crushed nose and wrecked engine bay
  and tumbles along the road. What's lost matters if Effects is on:
  - no radiator: the engine overheats
  - no intake: the engine loses power
  - no battery: the engine dies
  - a knocked-out headlight goes dark
  - a wrecked front corner bends the steering arm, so you lose much of the steering lock on that side

  The engine bay isn't solid either: the engine, radiator and the rest bend and crumple with the frame.
- **Inside parts:** there's a full engine bay and running gear under the panels, and they bend with the frame.
  When the bonnet or bumpers come off you see a V6 with red valve covers, the intake plenum, an air box, a
  battery, strut towers and a radiator with fans. Underneath are the frame rails, control arms, driveshaft,
  exhaust, fuel tank and diff. With a door gone you see the seats and cabin.
- **The underside bends too:** only the floor's centre spine is held, softly, so the sills and floor fold with
  the rest of the body.

The bending is done on the graphics card (the body's own vertices are moved), so it doesn't cost frame rate.

## Smoke
Smoke comes from billowing, lit cloud puffs (`smoke_fx.gd`):
- **Tyre smoke** pours from the rear contact patches when you drift or spin the wheels. It swirls, swells to
  several metres, lingers in the air behind you, and takes the sun's light (brighter in sunlight, darker in
  shadow).
- **A damaged engine** gives off white steam from a hit radiator or a hot engine, and thick dark smoke once the
  engine itself is wrecked or overheating.

It's tuned to cost almost nothing: full tyre smoke for a whole lap measured 79 fps against 81 without.

## Crash feel and sounds
Crashes soak up energy instead of bouncing:
- A hard hit is almost entirely plastic, so a head-on into a tree at 90 km/h stops the car dead, while light
  taps still rebound a little.
- Glancing hits scrape speed off, and offset hits spin the car round the tree.
- The body lurches with the impact: the nose dives on a frontal hit and the body rolls on a side hit.
- Nose and roof landings are heavily damped.
- The camera shakes in proportion to the hit.

Crashes use real recorded sounds (all CC0, credited in `game/sounds/CREDITS.md`): car crash recordings for
big and medium hits, metal hits and sheet-metal bangs for light hits and guardrails, metal slams on top of big
impacts, wood splintering when you hit a tree, breaking glass, falling metal for parts hitting the road, and a
real metal-scrape loop. The files load straight from `game/sounds/`, and the synthesised versions
(`crash_audio.gd`, `--dumpsounds=dir`) are only used if a file is missing. The radiator steam hiss is
synthesised.

`--crashtest [--side] [--speed=N] [--repair]` with `--shot=dir` is a test that drives into a tree, prints what
broke and takes screenshots.

## Body physics and air time
The car body is a sprung rigid body. Four spring/damper wheels push it up wherever they touch the ground,
gravity pulls it down, and its height, pitch and roll are simulated, not copied from the road. It squats,
dives and leans with weight transfer, rides over bumps and the gravel shoulders, and can tip onto three
wheels. A wheel that goes light loses its grip. The chassis and roof can scrape the ground too, and the car
resets itself if it ends up stuck on its side or roof.

It leaves the ground whenever the road drops away faster than gravity pulls it down. Greenwood Circuit has three
jump crests on its straightest stretches. Hit them at 90+ km/h, and fast hilltops will launch you too. In the air the tires do nothing, the car keeps whatever spin and pitch it
took off with, and it lands on its suspension. Every jump longer than 0.3 s scores points.
`--edgetest --speed=N` is a headless test that drives off and back onto the road edge.

## Settings (F2)
The panel has five tabs: **World** (time and weather), **Graphics** (grass and baked lighting), **Car** (damage and effects),
**Display** and **Audio** (Master, Engine, Tyre squeal, Crashes / impacts and Music volume). Display switches each on-screen readout on or off: frame rate, ping, engine status, tyre and
wheel status (one line per wheel with its condition in %), and the minimap.

If the car ends up on its roof or side, it stays there. A hint tells you to press **R** to put it back on the
road. Hard landings from big jumps hit with a solid thud instead of bouncing.

Time of day (slider plus Dawn / Morning / Noon / Sunset / Night buttons) and weather (Clear, Hazy, Cloudy,
Foggy, Rain, Snow). Both can **cycle** automatically: a full day can take 2–40 minutes, and the weather can change
every 1–10 minutes with smooth transitions. Headlights switch on by themselves when it gets dark. Rain is
overcast but easy to see through: fine, faint streaks, with a darker, shinier wet road. Snow covers the ground
and the grass, but the road stays clear and the car drives as normal. Settings are saved.

Press **F1** (or the menu's Controls button) for the **Controls** screen, with Keyboard, Gamepad, VR and
Drifting tips tabs.

## Play

- **Easiest:** double-click `play.bat`.
- **In the editor:** run `tools\godot\Godot_v4.3-stable_win64.exe`, import `game\project.godot`, then press F5.

### VR
Plug in your headset with SteamVR (or Quest Link / Air Link) running, with SteamVR set as the
OpenXR runtime, then launch the game. It detects the headset and starts in VR automatically (no
setting needed); without a headset it runs on the desktop as usual.

In VR you start standing in the forest in front of the full menu on a floating screen: maps, biome,
Settings, Caches, Inventory and updates. Point either controller at it (an orange laser) and pull the
trigger to click; the thumbstick scrolls. Picking a map puts you in the driver's seat with the HUD
(speed, score, points, lap, minimap) floating above the dash. The menu button takes you back to the menu.
Your view is put exactly at the driver's eyes (your real head height is cancelled out; Y recenters).
You have gloved hands (`vr_hand.gd`); squeeze grip with a hand on the steering wheel rim to take hold of
it, then turn it like a real wheel (18:1 to the front wheels, less at speed; hand over hand works). Letting go hands the
steering back to the thumbstick.

**Cars:** Inventory > Cars picks what you drive: the original procedural 350Z, or the CC96 by IceMaan
(CC0, `game/models/cars/cc96/`, FBX loaded at runtime) in three versions - Street (kit 1), Sport (kit 2 +
wing) and Race (kit 3 + wing), each with its own rims. `car_model_ext.gd` builds a downloaded car and
gives it the same wheels, steering wheel, VR hands, lights, brake lights, skins, dents and dash readout as
the 350Z; all cars share the same physics. To add another car, add an entry to `CARS` in `profile.gd`.
The VR hands are the CC0 glove model and animations from Godot XR Tools (`game/models/hands/`).

**Mirrors:** both door mirrors and the rear-view mirror really work: each one renders what's behind
from the mirror (flipped like a mirror). They only render from the driver's seat (cockpit view and VR),
since each mirror draws the world again.
(`vr_panel.gd` draws the normal 2D menu into a SubViewport on a quad and turns the laser into mouse
events. Dev aid: `--vrsim` runs the VR menu on the desktop and `--vrclick=Caches,Close` clicks through it.)

| VR control | Action |
|---|---|
| Right trigger | Throttle |
| Left trigger | Brake / reverse |
| Left thumbstick | Steer |
| Grip with a hand on the steering wheel rim | Grab the wheel and steer with your hands (one or both) |
| A | Handbrake |
| B | Reset car onto the road |
| X (left) | Restart from the start line |
| Y / stick click | Recenter view |
| Menu button (left) | Back to the menu |
| Trigger (on the menu) | Click where the laser points |
| Thumbstick up/down (on the menu) | Scroll |

### Keyboard / gamepad
| Key | Pad | Action |
|---|---|---|
| Enter | Start | Drive the last played map (start screen) |
| Esc | Start | Back to the map select screen (while driving) |
| W / Up | RT | Throttle |
| S / Down | LT | Brake (hold when stopped = reverse) |
| A D / Left Right | Left stick | Steer |
| Space | A | Handbrake |
| C | B | Camera: chase / hood / cockpit |
| R | Y | Reset onto the road |
| Backspace | Back/View | Restart from the start line (resets lap time and lap count, keeps best lap) |
| Q / E | LB / RB | Manual shift (M returns to auto) |
| H | | Headlights |
| Right-mouse drag | | Orbit the chase camera |
| F1 / F2 / F11 | | Controls / Settings / fullscreen |

**Drifting:** turn in, tap the handbrake (or stab the throttle in 2nd), then balance the angle with
throttle. Countersteer assist helps on keyboard. Points build while you slide on the road at more
than 10° of angle. The multiplier rises the longer you hold it. Leaving the road or hitting a tree
or a guardrail hard loses the combo.

## Project layout
```
game/
  project.godot        settings (OpenXR on, Forward+)
  main.tscn            single scene; everything is built from scripts
  scripts/
    main.gd            world setup, sky/fog/sun, input map, VR rig, map choice
    track.gd           closed-loop spline road, elevation, terrain, height/distance queries
    hill_track.gd      Switchback Ridge map: hill shape, switchbacks, guardrails (+ collision), street lamps
    circuit_track.gd   Compass Raceway map: race circuit traced from a drawing (builds on hill_track.gd)
    endless_track.gd   streamed never-ending road
    forest.gd          procedural trees (branch skeleton + compound-leaf cards), LOD chunks, collisions
    grass.gd           streamed grass tufts with wind
    mountains.gd       horizon mountain ring with weather haze
    env_controller.gd  time of day, weather, rain / snow particles
    car_model.gd       the 350Z: lofted body, wheel arches, glasshouse, lights, wheels, interior
    car.gd             drift physics (tyre model, RWD drivetrain, sprung body, assists), scoring, smoke, skids
    camera_rig.gd      chase / hood / cockpit cameras
    hud.gd             speed, gear, tach, drift combo, laps, minimap, menus
    engine_audio.gd    synthesised V6 + tyre squeal
    mb.gd              mesh-building helpers
```
Tweak points: the road shape is the `ctrl` list in `track.gd` (and in `hill_track.gd` / `circuit_track.gd` (its `LINE`) for the other maps),
the car colour is `paint_color` in `car_model.gd`, and the handling numbers are the constants at the top of
`car.gd`.
