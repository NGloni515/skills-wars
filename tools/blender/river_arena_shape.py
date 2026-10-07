import math

# Terrain extends well past the play area so the camera never sees its edge.
HALF_X = 32.0
HALF_Z = 26.0
PLAY_HALF_X = 14.4
PLAY_HALF_Z = 12.0
RIVER_EDGE = 2.45
WATER_HALF_WIDTH = 2.03
WATER_PLANE_HALF_WIDTH = 2.94
WATER_LEVEL = -0.3
RIVER_BED = -0.95
SHORE_TOP = 2.42
SHORE_WOBBLE = (0.12, 0.06)
SLOPE_WIDTH = 0.8

GRASS_A = (0.3, 0.56, 0.2)
GRASS_B = (0.4, 0.64, 0.25)
GRASS_EDGE = (0.55, 0.66, 0.3)
HILL = (0.24, 0.46, 0.18)
SAND = (0.91, 0.8, 0.56)
WET_SAND = (0.66, 0.57, 0.4)
RIVERBED = (0.4, 0.42, 0.34)


def smoothstep(edge0, edge1, x):
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def shore_top(x, z):
    # The east bank mirrors the west bank through the center, so both teams get the same shoreline.
    zz = z if x < 0 else -z
    return SHORE_TOP + SHORE_WOBBLE[0] * math.sin(zz * 0.55) + SHORE_WOBBLE[1] * math.sin(zz * 1.31 + 1.7)


def bank_t(x, z):
    top = shore_top(x, z)
    return smoothstep(top - SLOPE_WIDTH, top, abs(x))


def hills(x, z):
    edge = max(
        smoothstep(PLAY_HALF_X + 1.5, PLAY_HALF_X + 9.0, abs(x)),
        smoothstep(PLAY_HALF_Z + 1.5, PLAY_HALF_Z + 8.0, abs(z)),
    )
    return edge * (0.7 + 0.45 * math.sin(x * 0.45) * math.cos(z * 0.38))


def ripple(x, z):
    return 0.03 * math.sin(x * 1.7 + z * 0.9) * math.cos(z * 1.3 - x * 0.4)


def height(x, z):
    t = bank_t(x, z)
    return RIVER_BED * (1.0 - t) + hills(x, z) + ripple(x, z) * t


def color(x, z, h):
    t = bank_t(x, z)
    variation = 0.5 + 0.5 * math.sin(x * 0.31 + math.sin(z * 0.23) * 2.0) * math.cos(z * 0.27 - x * 0.12)
    grass = mix(GRASS_A, GRASS_B, variation)
    grass = mix(grass, HILL, smoothstep(0.1, 0.9, hills(x, z)))
    grass = mix(GRASS_EDGE, grass, smoothstep(0.92, 1.0, t))
    if t >= 0.92:
        return grass
    sand = mix(WET_SAND, SAND, smoothstep(-0.45, -0.2, h))
    sand = mix(RIVERBED, sand, smoothstep(-0.85, -0.55, h))
    return mix(sand, grass, smoothstep(0.8, 0.92, t))
