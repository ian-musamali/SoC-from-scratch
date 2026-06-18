#pragma once
#include <stdint.h>

// AXI address map (matches axi4lite_fabric.sv decode)
#define BRAM_BASE       0x00000000u
#define UART_BASE       0x10000000u
#define VGA_FB_BASE     0x20000000u
#define GPU_BASE        0x30000000u

// GPU MMIO register offsets (relative to GPU_BASE)
#define GPU_CTRL        (*(volatile uint32_t *)(GPU_BASE + 0x00))
#define GPU_STATUS      (*(volatile uint32_t *)(GPU_BASE + 0x04))
#define PLAYER_X        (*(volatile uint32_t *)(GPU_BASE + 0x08))
#define PLAYER_Y        (*(volatile uint32_t *)(GPU_BASE + 0x0C))
#define PLAYER_ANG      (*(volatile uint32_t *)(GPU_BASE + 0x10))
#define GPU_CYCLES      (*(volatile uint32_t *)(GPU_BASE + 0x14))
#define CORE_UTIL       (*(volatile uint32_t *)(GPU_BASE + 0x18))
#define DMA_CTRL        (*(volatile uint32_t *)(GPU_BASE + 0x1C))
#define DMA_SRC         (*(volatile uint32_t *)(GPU_BASE + 0x20))
#define DMA_DST         (*(volatile uint32_t *)(GPU_BASE + 0x24))
#define DMA_LEN         (*(volatile uint32_t *)(GPU_BASE + 0x28))

// GPU_CTRL bits
#define GPU_CTRL_FRAME_START  (1u << 0)
#define GPU_CTRL_FRAME_DONE   (1u << 1)

// UART Lite registers (Xilinx AXI UART Lite compatible offsets)
#define UART_RX         (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_TX_REG     (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_STAT       (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_CTRL_REG   (*(volatile uint32_t *)(UART_BASE + 0x0C))

// UART_STAT bits
#define UART_STAT_TX_EMPTY  (1u << 2)
#define UART_STAT_RX_VALID  (1u << 0)

// Q16.16 fixed-point helpers
typedef int32_t q1616_t;

#define Q(x)         ((q1616_t)((x) * 65536.0))   // float → Q16.16
#define QF(q)        ((double)(q) / 65536.0)        // Q16.16 → float (debug only)

// 64×64 map: 1=wall, 0=floor
// Must be loaded to each GPU core's map BRAM at startup.
#define MAP_SIZE 64
extern const uint8_t DOOM_MAP[MAP_SIZE][MAP_SIZE];
