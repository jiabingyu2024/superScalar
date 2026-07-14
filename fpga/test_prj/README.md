# PYNQ-Z2 board validation

This directory contains an isolated PYNQ-Z2 build. It only references the CPU/SoC
RTL and test images outside this directory; all generated Vivado files stay under
`fpga/test_prj/build/`.

## Hardware setup

1. Fit the EES_363DP digital daughterboard to the PYNQ-Z2 Arduino headers.
2. Set daughterboard power switch `SW7` to `ON`.
3. Power the PYNQ-Z2 and connect its programming USB/JTAG port.
4. Leave the Ethernet PHY operational because its 125 MHz output drives PL pin
   `H16`. Press `BTN0` at any time to reset and rerun the test.

The PYNQ-Z2 and EES_363DP digital I/O are 3.3 V. Do not apply 5 V to an Arduino
signal pin.

## Build and program

### Vivado GUI Tcl Console on Windows

Start Vivado normally, then enter the following commands in the GUI **Tcl
Console**. Use forward slashes in the Windows path:

```tcl
cd {E:/Resources/03_competitions/26_03_jcs/2607round/superScalar}
set ::env(FPGA_MEM_PROFILE) srcWithMext
set ::env(FPGA_CPU_CLK_MHZ) 50.000
source fpga/test_prj/create_project.tcl
```

The project is created and opened at
`fpga/test_prj/build/srcWithMext/pynq_superscalar.xpr`. To build the bitstream
from the same GUI Tcl Console:

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

The generated bitstream is:

```text
fpga/test_prj/build/srcWithMext/pynq_superscalar.runs/impl_1/pynq_top.bit
```

To use the shorter validated smoke image, change `FPGA_MEM_PROFILE` to
`srcSmoke`. The PYNQ wrapper PLL is fixed at 50 MHz, so keep
`FPGA_CPU_CLK_MHZ` at `50.000`.

### Windows PowerShell batch mode

From the repository root, run:

```powershell
vivado -mode batch -source fpga/test_prj/build_bitstream.tcl -tclargs srcSmoke 4
vivado -mode batch -source fpga/test_prj/program_board.tcl -tclargs srcSmoke
```

The default `srcSmoke` image is used because the repository simulation already
observes its PASS signature and elapsed-time display. A different data directory
containing both `irom.coe` and `dram.coe` can be selected by replacing `srcSmoke`
in both commands.

To create the project without running synthesis or implementation:

```powershell
vivado -mode batch -source fpga/test_prj/create_project.tcl -tclargs srcSmoke
```

Open `fpga/test_prj/build/srcSmoke/pynq_superscalar.xpr` for an interactive run.

## What to observe

| Output | Meaning |
|---|---|
| `LED0` blinking | CPU test is still running |
| `LED1` solid | PASS signature `0x01221c08` was observed |
| `LED2` solid | FAIL signature `0x24181824` was observed |
| `LED3` | Current display page; it mirrors `SW0` |
| `SW0 = 0` | Daughterboard shows the low four digits, normally elapsed milliseconds |
| `SW0 = 1` | Daughterboard shows the high four digits/test-count fields |
| `BTN0` | Reset and rerun |

For the current `srcSmoke` reference result, the final SoC display value is
`0x37000797`: with `SW0=0`, the daughterboard shows `0797`, and `LED1` is solid.
Actual FPGA time may differ slightly, but a solid `LED1` plus a stable numeric
time is the intended success indication.

The daughterboard LED1..LED8 signals share the same physical pins as the eight
seven-segment segment lines. Their illumination while the display is active is
therefore not an independent status indication; use the four PYNQ-Z2 board LEDs.

## Pin-source notes

- PYNQ-Z2 user manual: PL clock `H16`, board buttons/switches/LEDs, and Arduino
  header FPGA mappings.
- EES_363DP digital daughterboard manual: common-anode display, active-low digit
  selection through 2N5401 devices, and segment/digit pin mappings.
- PYNQ-Z2 schematic: cross-check of `SYSCLK` and Arduino net names.
