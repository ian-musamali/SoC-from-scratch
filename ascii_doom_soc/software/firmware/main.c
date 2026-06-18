#include <stdint.h>

// -----------------------------------------------------------------------
// MMIO
// -----------------------------------------------------------------------
#define GPU_CTRL    (*(volatile uint32_t*)0x30000000u)
#define GPU_STATUS  (*(volatile uint32_t*)0x30000004u)
#define PLAYER_X    (*(volatile uint32_t*)0x30000008u)
#define PLAYER_Y    (*(volatile uint32_t*)0x3000000Cu)
#define PLAYER_ANG  (*(volatile uint32_t*)0x30000010u)
#define GPU_CYCLES  (*(volatile uint32_t*)0x30000014u)

#define UART_TX     (*(volatile uint32_t*)0x10000000u)
#define UART_STAT   (*(volatile uint32_t*)0x10000004u)

// -----------------------------------------------------------------------
// Q16.16 helpers
// -----------------------------------------------------------------------
// 2*pi in Q16.16 = 411775  (6.28318... * 65536)
#define TWO_PI_Q    411775u
// 1 degree in Q16.16 = 1144  (1/360 * 411775)
#define DEG_Q       1144u

static inline int32_t q(float x) { return (int32_t)(x * 65536.0f); }

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

    uart_puts("\r\nASCII Doom SoC booted\r\n");

    PLAYER_X = q(2.5f);
    PLAYER_Y = q(2.5f);

    uint32_t frame = 0;
    while (1) {
        PLAYER_ANG = angle;

        // Trigger frame
        GPU_CTRL = 1u;

        // Wait for frame_done (bit 1)
        while (!(GPU_CTRL & 2u)) {}

        // Rotate ~1 degree per frame
        angle += DEG_Q;
        if (angle >= TWO_PI_Q) angle -= TWO_PI_Q;

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
