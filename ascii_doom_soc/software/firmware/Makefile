TOOLCHAIN  = riscv64-unknown-elf
ARCH       = rv32im
ABI        = ilp32
CFLAGS     = -march=$(ARCH) -mabi=$(ABI) -O2 -nostdlib -ffreestanding \
             -Wall -ffunction-sections -fdata-sections
LDFLAGS    = -T linker.ld -Wl,--gc-sections
BRAM_WORDS = 65536

.PHONY: all clean disasm size

all: firmware.hex map.hex

firmware.elf: startup.S main.c linker.ld
	$(TOOLCHAIN)-gcc $(CFLAGS) $(LDFLAGS) -o $@ startup.S main.c

firmware.bin: firmware.elf
	$(TOOLCHAIN)-objcopy -O binary $< $@

firmware.hex: firmware.bin elf2hex.py
	python3 elf2hex.py $< $@ $(BRAM_WORDS)

map.hex: gen_map_hex.py
	python3 gen_map_hex.py

disasm: firmware.elf
	$(TOOLCHAIN)-objdump -d $<

size: firmware.elf
	$(TOOLCHAIN)-size $<

clean:
	rm -f firmware.elf firmware.bin firmware.hex map.hex
