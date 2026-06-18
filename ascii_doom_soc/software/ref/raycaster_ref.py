"""
raycaster_ref.py — Reference DDA raycaster for ASCII Doom SoC
64×64 map, 80-column output, ASCII brightness brackets
"""

import math

# ---------------------------------------------------------------------------
# 64×64 map: '1' = wall, '0' = floor
# Row 0, row 63: all walls; col 0, col 63: walls in every row
# Room 1: rows 5-15, cols 5-25  (opening east at row 10, col 25)
# Room 2: rows 5-15, cols 30-50 (openings west row 10 col 30, east row 10 col 50)
# Room 3: rows 18-30, cols 40-60 (opening north at row 18, col 45)
# Dead-end: col 45 corridor rows 8-18, dead-end walls rows 8 cols 43-47
# ---------------------------------------------------------------------------

def _build_map():
    rows = []
    for r in range(64):
        row = list('0' * 64)
        # outer walls
        if r == 0 or r == 63:
            rows.append('1' * 64)
            continue
        row[0] = '1'
        row[63] = '1'

        # Room 1 walls: rows 5..15, cols 5..25
        if 5 <= r <= 15:
            if r == 5 or r == 15:
                for c in range(5, 26):
                    row[c] = '1'
            else:
                row[5] = '1'
                # east wall with opening at row 10
                if r != 10:
                    row[25] = '1'

        # Room 2 walls: rows 5..15, cols 30..50
        if 5 <= r <= 15:
            if r == 5 or r == 15:
                for c in range(30, 51):
                    row[c] = '1'
            else:
                # west wall with opening at row 10
                if r != 10:
                    row[30] = '1'
                # east wall with opening at row 10
                if r != 10:
                    row[50] = '1'

        # Room 3 walls: rows 18..30, cols 40..60
        if 18 <= r <= 30:
            if r == 30:
                for c in range(40, 61):
                    row[c] = '1'
            elif r == 18:
                # north wall with opening at col 45
                for c in range(40, 61):
                    if c != 45:
                        row[c] = '1'
            else:
                row[40] = '1'
                row[60] = '1'

        # Dead-end corridor: col 45, rows 8..18
        # Side walls at col 44 and col 46 for rows 8..17
        # Dead-end cap at row 8, cols 43..47
        if r == 8:
            for c in range(43, 48):
                row[c] = '1'
        elif 9 <= r <= 17:
            # Only add side walls if not already a room wall
            if row[44] == '0':
                row[44] = '1'
            if row[46] == '0':
                row[46] = '1'

        rows.append(''.join(row))
    return rows


MAP = _build_map()

# Ensure player start (2,2) integer cell is floor
assert MAP[2][2] == '0', f"Player start cell is not floor: {MAP[2][2]}"

# ASCII distance brackets — index by distance
_BRACKETS = '#%*+=-:.'
_DIST_THRESHOLDS = [1.0, 1.5, 2.5, 4.0, 6.0, 9.0, 14.0]


def _dist_to_char(d):
    thresholds = _DIST_THRESHOLDS
    if d < thresholds[0]:
        return _BRACKETS[0]
    elif d < thresholds[1]:
        return _BRACKETS[1]
    elif d < thresholds[2]:
        return _BRACKETS[2]
    elif d < thresholds[3]:
        return _BRACKETS[3]
    elif d < thresholds[4]:
        return _BRACKETS[4]
    elif d < thresholds[5]:
        return _BRACKETS[5]
    elif d < thresholds[6]:
        return _BRACKETS[6]
    else:
        return _BRACKETS[7]


def _cast_ray(px, py, ray_angle):
    """DDA ray cast. Returns perpendicular distance to first wall hit."""
    cos_a = math.cos(ray_angle)
    sin_a = math.sin(ray_angle)

    # Avoid division by zero
    eps = 1e-10
    if abs(cos_a) < eps:
        cos_a = eps
    if abs(sin_a) < eps:
        sin_a = eps

    # Current map cell
    map_x = int(px)
    map_y = int(py)

    # Step direction
    step_x = 1 if cos_a > 0 else -1
    step_y = 1 if sin_a > 0 else -1

    # Length of ray from one x/y side to next
    delta_x = abs(1.0 / cos_a)
    delta_y = abs(1.0 / sin_a)

    # Initial side distances
    if cos_a > 0:
        side_dist_x = (map_x + 1.0 - px) * delta_x
    else:
        side_dist_x = (px - map_x) * delta_x

    if sin_a > 0:
        side_dist_y = (map_y + 1.0 - py) * delta_y
    else:
        side_dist_y = (py - map_y) * delta_y

    # DDA loop
    hit_side = 0  # 0 = x side, 1 = y side
    for _ in range(512):
        if side_dist_x < side_dist_y:
            side_dist_x += delta_x
            map_x += step_x
            hit_side = 0
        else:
            side_dist_y += delta_y
            map_y += step_y
            hit_side = 1

        # Bounds check
        if map_x < 0 or map_x >= 64 or map_y < 0 or map_y >= 64:
            return 64.0  # hit boundary

        if MAP[map_y][map_x] == '1':
            # Compute perpendicular wall distance (fisheye correction built in)
            if hit_side == 0:
                perp = side_dist_x - delta_x
            else:
                perp = side_dist_y - delta_y
            return max(perp, 0.001)

    return 64.0


def render(px, py, angle):
    """
    Render 80 screen columns from position (px, py) facing angle (radians).
    Returns an 80-character string.
    """
    cols = 80
    result = []
    for col in range(cols):
        # Ray angle with fisheye-corrected FOV using atan2
        ray_angle = angle + math.atan2(col - 40, 60.0)
        dist = _cast_ray(px, py, ray_angle)
        # Fisheye correction: perpendicular distance
        dist_perp = dist * math.cos(ray_angle - angle)
        result.append(_dist_to_char(dist_perp))
    return ''.join(result)


def main():
    # Start position (2.5, 2.5) facing east (0.0 radians)
    line = render(2.5, 2.5, 0.0)
    print(line)


if __name__ == '__main__':
    main()
