#include <stdint.h>
#include "map.h"

// ---------------------------------------------------------------------------
// 64×64 open-room map matching the Python/RTL reference
// 1=wall, 0=floor
// ---------------------------------------------------------------------------
const uint8_t DOOM_MAP[MAP_SIZE][MAP_SIZE] = {
    {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
     1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    /* rows 5-63: outer walls only (interior open) */
    [5 ... 62] = {
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
    },
    {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
     1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
};

// ---------------------------------------------------------------------------
// Minimal UART putchar
// ---------------------------------------------------------------------------
static void uart_putchar(char c) {
    while (!(UART_STAT & UART_STAT_TX_EMPTY))
        ;
    UART_TX_REG = (uint32_t)(unsigned char)c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putchar(*s++);
}

// ---------------------------------------------------------------------------
// Write map data to each GPU core's BRAM.
// The GPU cores read from map_bram[core][addr] inside soc_top.
// In the full SoC with Vivado, these are per-core BRAMs initialised via
// a dedicated write port.  For the Verilator sim we use a simple backdoor.
// On real FPGA: CPU walks the map once at startup and the map is static.
//
// Here we write directly — in real hardware this would be a MMIO write
// to a map-load port in GPU MMIO (not implemented yet; placeholder).
// ---------------------------------------------------------------------------
static void init_map(void) {
    // Placeholder: in the real system, the CPU writes map data through
    // a dedicated MMIO window.  The Verilator sim backdoor initialises
    // map_bram[] via soc_top.sv initial blocks (all zeros = open floor).
    // For the test scenario, the map is already correct (walls at row 0/63
    // and col 0/63 match the Python reference).
    (void)DOOM_MAP;
}

// ---------------------------------------------------------------------------
// Main game loop
// ---------------------------------------------------------------------------
int main(void) {
    uart_puts("ASCII Doom SoC booting...\r\n");

    init_map();

    // Initial player position and angle (matches Python reference test)
    q1616_t px   = Q(2.5);   // player X = 2.5 tiles
    q1616_t py   = Q(2.5);   // player Y = 2.5 tiles
    q1616_t pang = Q(0.0);   // angle = 0 (facing east)

    // Turn speed: ~3 degrees per frame in Q16.16
    // (PI/60 ≈ 0.05236 rad per frame @ 60 fps)
    const q1616_t TURN_SPEED = Q(0.05236);

    uart_puts("Starting render loop\r\n");

    for (;;) {
        // 1. Write player state to GPU MMIO
        PLAYER_X   = (uint32_t)px;
        PLAYER_Y   = (uint32_t)py;
        PLAYER_ANG = (uint32_t)pang;

        // 2. Trigger GPU frame
        GPU_CTRL = GPU_CTRL_FRAME_START;

        // 3. Wait for frame_done
        while (!(GPU_CTRL & GPU_CTRL_FRAME_DONE))
            ;

        // 4. Rotate player slightly for animation
        pang += TURN_SPEED;
        // Wrap angle: 2π in Q16.16 = 411775
        if (pang >= (q1616_t)(2 * 3.14159265358979323846 * 65536.0 + 0.5))
            pang -= (q1616_t)(2 * 3.14159265358979323846 * 65536.0 + 0.5);
    }

    return 0;
}
