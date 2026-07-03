#include <stdint.h>
#include "trig_lut.h"
#include "map_data.h"

// -----------------------------------------------------------------------
// MMIO
// -----------------------------------------------------------------------
#define GPU_CTRL    (*(volatile uint32_t*)0x30000000u)
#define GPU_STATUS  (*(volatile uint32_t*)0x30000004u)
#define PLAYER_X    (*(volatile uint32_t*)0x30000008u)
#define PLAYER_Y    (*(volatile uint32_t*)0x3000000Cu)
#define PLAYER_ANG  (*(volatile uint32_t*)0x30000010u)
#define GPU_CYCLES  (*(volatile uint32_t*)0x30000014u)
#define GPU_BUTTONS (*(volatile uint32_t*)0x3000001Cu)

#define UART_TX     (*(volatile uint32_t*)0x10000000u)
#define UART_STAT   (*(volatile uint32_t*)0x10000004u)

// Button bits, matching soc_top's {btnc, btnr, btnl, btnd, btnu} packing
#define BTN_U       (1u << 0)   // forward
#define BTN_D       (1u << 1)   // backward
#define BTN_L       (1u << 2)   // turn left
#define BTN_R       (1u << 3)   // turn right
#define BTN_C       (1u << 4)   // reserved (future: fire)

// -----------------------------------------------------------------------
// Q16.16 helpers
// -----------------------------------------------------------------------
// 2*pi in Q16.16 = 411775  (6.28318... * 65536)
#define TWO_PI_Q    411775u
// 1 degree in Q16.16 = 1144  (1/360 * 411775)
#define DEG_Q       1144u

#define MOVE_SPEED_Q  3277   // ~0.05 tiles/frame in Q16.16
#define TURN_SPEED_Q  (2u * DEG_Q)

static inline int32_t q(float x) { return (int32_t)(x * 65536.0f); }

// angle_q is a Q16.16 radian value in [0, TWO_PI_Q); TRIG_LUT_N must be a
// power of two for the masks below to work.
static inline int32_t lut_sin(uint32_t angle_q) {
    uint32_t idx = (angle_q * (uint32_t)TRIG_LUT_N) / TWO_PI_Q;
    return sin_lut[idx & (TRIG_LUT_N - 1)];
}

static inline int32_t lut_cos(uint32_t angle_q) {
    uint32_t idx = (angle_q * (uint32_t)TRIG_LUT_N) / TWO_PI_Q;
    return sin_lut[(idx + TRIG_LUT_N / 4) & (TRIG_LUT_N - 1)];
}

// Wall test against the same map baked into hardware map_bram (map_data.h,
// generated alongside map.hex from one shared MAP_STR — see gen_map_hex.py).
// Out-of-range counts as a wall so a stray move can't index past the array.
static inline int tile_is_wall(int32_t x_q, int32_t y_q) {
    int32_t tx = x_q >> 16;
    int32_t ty = y_q >> 16;
    if (tx < 0 || tx >= MAP_SIZE || ty < 0 || ty >= MAP_SIZE) return 1;
    return game_map[(uint32_t)ty * MAP_SIZE + (uint32_t)tx] != 0;
}

// -----------------------------------------------------------------------
// Minimal UART (poll-and-send)
// -----------------------------------------------------------------------
static void uart_putc(char c) {
    // bit 0 of UART_STAT = TX busy; wait until clear
    while (UART_STAT & 1u) {}
    UART_TX = (uint32_t)(unsigned char)c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_puthex(uint32_t v) {
    static const char hex[] = "0123456789abcdef";
    uart_putc('0'); uart_putc('x');
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(hex[(v >> i) & 0xF]);
}

// -----------------------------------------------------------------------
// main
// -----------------------------------------------------------------------
void main(void) {
    uint32_t angle = 0;
    int32_t  px = q(2.5f);
    int32_t  py = q(2.5f);

    uart_puts("\r\nASCII Doom SoC booted\r\n");

    PLAYER_X = (uint32_t)px;
    PLAYER_Y = (uint32_t)py;

    uint32_t frame = 0;
    while (1) {
        uint32_t btns = GPU_BUTTONS;

        // Turn — no collision needed for rotation
        if (btns & BTN_L) {
            angle += TURN_SPEED_Q;
            if (angle >= TWO_PI_Q) angle -= TWO_PI_Q;
        }
        if (btns & BTN_R) {
            angle = (angle >= TURN_SPEED_Q) ? (angle - TURN_SPEED_Q)
                                             : (angle + TWO_PI_Q - TURN_SPEED_Q);
        }

        // Move forward/back along the facing direction. Each axis is checked
        // (and, if blocked, held) independently so the player slides along a
        // wall instead of stopping dead when moving into it at an angle.
        if (btns & BTN_U) {
            int32_t dx = (lut_cos(angle) * MOVE_SPEED_Q) >> 16;
            int32_t dy = (lut_sin(angle) * MOVE_SPEED_Q) >> 16;
            if (!tile_is_wall(px + dx, py)) px += dx;
            if (!tile_is_wall(px, py + dy)) py += dy;
        }
        if (btns & BTN_D) {
            int32_t dx = (lut_cos(angle) * MOVE_SPEED_Q) >> 16;
            int32_t dy = (lut_sin(angle) * MOVE_SPEED_Q) >> 16;
            if (!tile_is_wall(px - dx, py)) px -= dx;
            if (!tile_is_wall(px, py - dy)) py -= dy;
        }

        PLAYER_X   = (uint32_t)px;
        PLAYER_Y   = (uint32_t)py;
        PLAYER_ANG = angle;

        // Trigger frame
        GPU_CTRL = 1u;

        // Wait for frame_done (bit 1)
        while (!(GPU_CTRL & 2u)) {}

        // Print a heartbeat every 64 frames
        if ((frame & 63u) == 0u) {
            uart_puts("frame ");
            uart_puthex(frame);
            uart_puts("  cycles=");
            uart_puthex(GPU_CYCLES);
            uart_puts("\r\n");
        }
        frame++;
    }
}
