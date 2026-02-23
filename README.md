# DivMMC Interface for ZX Spectrum

Verilog implementation of a DivMMC SD card interface for the Sinclair ZX Spectrum, targeting the Xilinx XC9572XL-VQ64 CPLD.

Originally designed by Mario Prato (2012) and converted from VHDL to Verilog.

---

## Overview

DivMMC is a memory-mapped SD card interface for the ZX Spectrum. It provides automatic paging of a shadow ROM and RAM bank into the lower 16K of the Z80 address space, triggered by specific instruction fetch addresses. Communication with the SD card is handled via a software-driven SPI engine clocked from the Z80 clock signal.

---

## Files

| File | Description |
|---|---|
| `divmmc.v` | Top-level Verilog module |
| `divmmc.ucf` | Pin location constraints for ISE |

---

## Target Hardware

- Device: Xilinx XC9572XL-VQ64
- Toolchain: Xilinx ISE (tested with 12.3)

Recommended fitter settings:

- Optimization: Speed
- Slew rate: Slow
- Pin termination: Float
- Global clock: Enabled
- Unused I/O: GND
- Macrocell power: Standard
- Logic optimization: Speed / Multi-level

---

## Interface

### Z80 Bus

| Signal | Direction | Description |
|---|---|---|
| `A[15:0]` | Input | Address bus |
| `D[7:0]` | Bidirectional | Data bus |
| `iorq` | Input | I/O request (active low) |
| `mreq` | Input | Memory request (active low) |
| `wr` | Input | Write strobe (active low) |
| `rd` | Input | Read strobe (active low) |
| `m1` | Input | M1 fetch cycle (active low) |
| `reset` | Input | System reset (active low) |
| `clock` | Input | Z80 clock from ULA (inverted from edge connector) |

### Memory Control

| Signal | Direction | Description |
|---|---|---|
| `romcs` | Output | Pages out the Spectrum ROM when high |
| `romoe` | Output | EEPROM output enable |
| `romwr` | Output | EEPROM write enable |
| `ramoe` | Output | RAM output enable |
| `ramwr` | Output | RAM write enable |
| `bankout[5:0]` | Output | RAM bank select |

### SPI

| Signal | Direction | Description |
|---|---|---|
| `card[1:0]` | Output | SD card chip selects (active low) |
| `spi_clock` | Output | SPI clock |
| `spi_dataout` | Output | MOSI |
| `spi_datain` | Input | MISO |

### Miscellaneous

| Signal | Direction | Description |
|---|---|---|
| `poweron` | Input | Power-on reset (active low pulse) |
| `eprom` | Input | Selects EEPROM mode via jumper |
| `mapcondout` | Output | High when DivMMC memory is paged in |

---

## I/O Ports

| Port | Address | Function |
|---|---|---|
| DivIDE control | `0xE3` | Writes bank select, MAPRAM, CONMEM bits |
| ZXMMC control | `0xE7` | Sets SD card chip-select lines |
| SPI data | `0xEB` | Triggers SPI byte transfer; read returns received byte |

---

## Automapping

The CPLD automatically pages in the DivMMC ROM and RAM when the Z80 fetches an instruction from any of the following addresses:

- `0x0000`, `0x0008`, `0x0038`, `0x0066`, `0x04C6`, `0x0562`
- Any address in the range `0x3D00`–`0x3DFF`

Paging remains active until execution leaves the mapped region, with the exception of the `0x1FF8`–`0x1FFF` range which is used for exit trampolines.

---

## Notes

- The Z80 clock input must be the logical inverse of the signal present on the Spectrum edge connector.
- The `mapram` bit in the control register is sticky: once set it can only be cleared by a power-on reset.
- The SPI engine shifts one byte per 16 Z80 clock half-cycles, producing 8 SPI clock pulses per transfer.
