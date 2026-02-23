# DivIDE / DivMMC Developer Reference

This document consolidates the programming model for DivIDE (original Zilog spec) and the DivMMC AllRAM extension (Mario, 23/01/2023).

---

## Hardware Overview

DivIDE contains:
- 8 kB ROM (absent, EPROM, or in-system-reprogrammable EEPROM)
- 32–512 kB RAM

All ports are decoded using **A0..A7 address wires only**.

---

## I/O Port Map

| Address (hex) | Dec | Direction | Register |
|---|---|---|---|
| `0xA3` | 163 | R/W | DATA (16-bit via byte pairs) |
| `0xA7` | 167 | R / W | ERROR / FEATURES |
| `0xAB` | 171 | R/W | SECTOR COUNT |
| `0xAF` | 175 | R/W | SECTOR NUMBER (LBA 0–7) |
| `0xB3` | 179 | R/W | CYLINDER LOW (LBA 8–15) |
| `0xB7` | 183 | R/W | CYLINDER HIGH (LBA 16–23) |
| `0xBB` | 187 | R/W | DRIVE/HEAD (LBA 24–28) |
| `0xBF` | 191 | R / W | STATUS / COMMAND |
| `0xE3` | 227 | W | DivIDE CONTROL REGISTER |
| `0x0F3B` | 3899 | R/W | DivMMC ZXMMC_ENABLE (AllRAM extension) |

IDE command block registers occupy addresses `xxxx xxxx 101r rr11` (rrr = 0..7).

For full IDE register semantics see: http://www.t13.org

---

## DATA REGISTER — ODD/EVEN Access Protocol

The DATA register is 16-bit, accessed as byte pairs:

**Reading:**
- **ODD** access → returns low byte; high byte is latched; buffer pointer advances.
- **EVEN** access → returns the previously latched high byte.

**Writing:**
- **ODD** access → byte is stored in latch.
- **EVEN** access → latched low byte + current high byte are written as a word to the drive.

The ODD/EVEN state is **reset to ODD** after any access to a non-data command block register (rrr = 1..7) or to the DivIDE CONTROL REGISTER. Accesses outside DivIDE ports have no effect on this state. State is **unknown** after reset or power-on.

---

## DivIDE Control Register (`0xE3`) — Write Only

```
  7        6      5  4  3  2   1       0
[ CONMEM, MAPRAM, X, X, X, X, BANK1, BANK0 ]
```

All bits reset to `0` on power-on. Unimplemented bits (X) must be zeroed for future compatibility.

| Bit | Name | Description |
|---|---|---|
| 7 | CONMEM | Forces DivIDE memory into `0000–1FFF` / `2000–3FFF` regardless of automapper state or EPROM presence. Bank in `2000–3FFF` is always writable. `0000–1FFF` is flash-writable when EPROM jumper is open. |
| 6 | MAPRAM | Sticky — can only be set to `1`; cleared only by power-on. Promotes RAM Bank 3 to act as EPROM/EEPROM substitute in `0000–1FFF`, write-protected. Use when no EPROM is fitted, or to safely test a loaded system image. |
| 1–0 | BANK1/0 | Selects the 8 kB RAM bank (0–3) mapped into `2000–3FFF` when DivIDE memory is active. |

### MAPRAM safe-load sequence

Because re-entering MAPRAM mode requires care to avoid leaving the automapper in a bad state:

1. `DI`
2. `CALL 1FFBh` (`RET` instruction — triggers automapper off via off-area)
3. Set `CONMEM`
4. Load system image into Bank 3
5. Release `CONMEM`, set `MAPRAM`
6. `EI`

---

## Memory Mapping

### Automatic mapping (entrypoints)

Automapping is active only when an EPROM/EEPROM is fitted (EPROM jumper closed) **or** MAPRAM is set.

DivIDE memory is mapped on the refresh cycle following an M1 fetch from:

| Address | Trigger |
|---|---|
| `0x0000` | RST 0 / power-on vector |
| `0x0008` | RST 8 |
| `0x0038` | INT / RST 38h |
| `0x0066` | NMI |
| `0x04C6` | |
| `0x0562` | |
| `0x3D00–0x3DFF` | Mapped instantly (100 ns after /MREQ falling) |

Memory is **automatically unmapped** on the refresh cycle of a fetch from the **off-area**: `0x1FF8–0x1FFF`.

### One-instruction delay trick

The one-instruction delay between fetch and mapping allows nested-call detection: place a different opcode at the entrypoint than the original ROM. The first call executes the original instruction (DivIDE not yet mapped); subsequent calls see the DivIDE opcode. This is the recommended approach for 100% nested-NMI prevention without combinatorial hardware.

### Memory layout summary

| Condition | `0000–1FFF` | `2000–3FFF` |
|---|---|---|
| CONMEM=1 | EEPROM/EPROM (writable if EPROM jumper open) | Selected bank, always writable |
| MAPRAM=1, CONMEM=0, entrypoint hit | Bank 3, read-only | Selected bank (writable if ≠ Bank 3) |
| MAPRAM=0, CONMEM=0, EPROM jumper closed, entrypoint hit | EEPROM/EPROM, read-only | Selected bank, always writable |
| Otherwise | Normal Spectrum memory — DivIDE inactive | |

Priority order (lowest → highest): EPROM jumper → MAPRAM → CONMEM.

---

## DivMMC AllRAM Extension

*Added 23/01/2023 by Mario. Requires DivMMC hardware.*

### ZXMMC_ENABLE Port (`0x0F3B` / dec 3899)

> Note: the originally proposed address `0xF3` (243) was discarded.

```
  D7       D6      D5           D4           D3–D0
[ ALLRAM, WRLOCK, MAPDISABLE, MAPRAM_PAGE, reserved ]
```

All bits cleared on power-on. **Reset does not clear these bits.**

| Bit | Name | Description |
|---|---|---|
| D7 | ALLRAM | Disables Spectrum ROM; maps DivMMC RAM into `0000–4000`. 8 pages on 128K DivMMC, 32 pages on 512K. |
| D6 | WRLOCK | Locks all writes to DivMMC RAM. |
| D5 | MAPDISABLE | Prevents automatic ROM mapping. SD card interface remains active. |
| D4 | MAPRAM_PAGE | Shifts MAPRAM page: `3` → `11` (128K) or `59` (512K). |
| D3–D0 | — | Reserved for future use. |

### RAM Page Addressing

Pages are selected using the Spectrum 128 paging registers (`7FFDh` bit 4, `1FFDh` bit 2) and the DivIDE CONTROL_PORT (`0xE3`).

With DivMMC paging **active**, only 2 pages are available. With paging **off** (MAPDISABLE=1), all RAM is accessible:

| Sel. bit | MAPDISABLE=0 | MAPDISABLE=1 |
|---|---|---|
| 4 | always 1 | `E3h` bit 5 *(512K only)* |
| 3 | always 1 | `E3h` bit 4 *(512K only)* |
| 2 | always 1 | `E3h` bit 3 |
| 1 | always 1 | `1FFDh` bit 2 |
| 0 | `7FFDh` bit 4 | `7FFDh` bit 4 |

This allows ZX Spectrum 48K, 128K, and +2A/+3 ROMs to be loaded into RAM and used as real ROMs.

### Other DivMMC Modifications vs Original DivMMC

1. **MAPRAM reset via `0xE3`:** Writing `%11XXXXXX` to the DivIDE Control Port (`0xE3`) when MAPRAM is set will now reset MAPRAM and set CONMEM (as suggested by Velesoft).
2. **`7FFDh` bit 4 latch:** Bit 4 of port `7FFDh` is implemented; when set, it disables further writes to that port (matching original 128K Spectrum behaviour). Cleared on reset.
3. **NMI button:** Disabled when CONMEM is active.

---

## References

- Original DivIDE programming model: Zilog (`xcimbal@quick.cz`)
- DivMMC AllRAM extension: Mario (23/01/2023)
- ATA/IDE register specification: http://www.t13.org
