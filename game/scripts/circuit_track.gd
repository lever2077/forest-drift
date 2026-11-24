# Compass Raceway: a race circuit traced from a track drawing. The start/finish
# is on the long bottom straight; from there the lap runs round the tall
# left-hand loop, through the U-turn and the esses in the middle, up the long
# diagonal to the top, round the right-hand lobe, down through the hairpin
# around the barrier, across the lower-right sweepers and back onto the
# straight. Gently rolling ground, guardrails on the outside of corners,
# floodlights along the track and trees dotted around the infield (built on
# the Switchback Ridge map code).
extends "res://scripts/hill_track.gd"

const SCALE := 1.15        # metres per pixel of the drawing
const ORIGIN := Vector2(405, 340)

# the black line of the drawing, in drawing pixels (x right, y down), in lap order
const LINE := [
	Vector2(385, 520), Vector2(250, 520), Vector2(120, 518), Vector2(96, 490), Vector2(100, 445),
	Vector2(122, 395), Vector2(118, 335), Vector2(96, 280), Vector2(92, 220), Vector2(102, 178),
	Vector2(135, 157), Vector2(180, 160), Vector2(212, 185), Vector2(232, 240), Vector2(250, 305),
	Vector2(278, 350), Vector2(312, 362), Vector2(335, 340), Vector2(340, 290), Vector2(333, 235),
	Vector2(338, 195), Vector2(390, 165), Vector2(450, 135), Vector2(510, 118), Vector2(560, 125),
	Vector2(605, 165), Vector2(635, 215), Vector2(635, 262), Vector2(600, 288), Vector2(540, 295),
	Vector2(490, 300), Vector2(468, 335), Vector2(472, 380), Vector2(505, 412), Vector2(555, 405),
	Vector2(605, 372), Vector2(660, 352), Vector2(705, 370), Vector2(718, 425), Vector2(712, 480),
	Vector2(685, 510), Vector2(620, 520), Vector2(500, 520),
]

func _init() -> void:
	var c: Array = []
	for p in LINE:
		c.append(((p as Vector2) - ORIGIN) * SCALE)
	ctrl = c
	G_MIN = Vector2(-460, -300)
	crest_count = 0
	smooth_win = 10
	blend_far = 12.0
	gantry_text = "COMPASS RACEWAY"
	grass_density = 1.2
	grass_height = 0.9
	clump.seed = 5
	clump.frequency = 0.02

# gently rolling parkland
func base_hill(x: float, z: float) -> float:
	return hills.get_noise_2d(x, z) * 4.0 + hills2.get_noise_2d(x, z) * 0.6

# a few trees dotted around the infield and outside, a proper forest further out
func tree_density(x: float, z: float, d: float) -> float:
	if d < 20.0:
		return 0.0
	var inside := sstep(440.0, 400.0, abs(x)) * sstep(300.0, 260.0, abs(z + 20.0))
	var c := clump.get_noise_2d(x, z)
	return lerpf(0.95, 0.3 + 0.65 * sstep(-0.05, 0.4, c), inside)
