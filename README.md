# fpga_trafficlight_fsm
# Traffic Light Controller (FSM) on FPGA – STEP-MAX10

A finite-state-machine (FSM) traffic light controller for a two-road intersection, written in Verilog,
verified with ten self-checking testbenches, and running on the **STEP-MAX10** board (Intel MAX 10 FPGA).

The project starts from the classic textbook specification (a 4-state Moore FSM with two vehicle sensors)
and extends it with the behaviour a real intersection needs: all-red clearance, minimum/maximum green,
gap-out, sensor filtering and a fault/start-up flashing mode.

## Features

- **7-state Moore FSM**: flashing-red (start-up / fault), A green, A yellow, all-red, B green, B yellow, all-red.
- **All-red clearance** (2 s) between the two phases so the intersection can empty.
- **Minimum green (5 s) and maximum green (20 s)** – no direction can be starved.
- **Gap-out**: green is extended while vehicles keep arriving and cut after a 3 s gap.
- **Demand latching**: the light only changes phase when the other road actually has a vehicle waiting.
- **Sensor filter**: 2-flip-flop synchroniser plus a 50 ms stability filter on the vehicle sensors.
- **Registered outputs**: lights are driven from flip-flops, so there are no combinational glitches on the outputs.
- **Start-up / fault mode**: both roads flash red for at least 4 s after reset or while the fault switch is on.
- All timing values are Verilog parameters.

## Architecture

Light codes (2 bits): `00` green, `01` yellow, `10` red, `11` off (used for blinking).

| State | Light A | Light B | Leaves the state when |
|---|---|---|---|
| F  | flashing red | flashing red | no fault and flashed >= `FLASH_SEC` -> S5 |
| S0 | green  | red    | `secs >= MIN_GREEN` and B is waiting and (`gap >= GAP_SEC` or `secs >= MAX_GREEN`) -> S1 |
| S1 | yellow | red    | `YELLOW_SEC` elapsed -> S2 |
| S2 | red    | red    | `ALLRED_SEC` elapsed -> S3 |
| S3 | red    | green  | `secs >= MIN_GREEN` and A is waiting and (`gap >= GAP_SEC` or `secs >= MAX_GREEN`) -> S4 |
| S4 | red    | yellow | `YELLOW_SEC` elapsed -> S5 |
| S5 | red    | red    | `ALLRED_SEC` elapsed -> S0 |

From any state, `fault = 1` goes to F. Reset also goes to F, so after power-up the sequence is
flashing red -> all-red -> A green.

### Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `MIN_GREEN` | 5 s | Minimum green time |
| `MAX_GREEN` | 20 s | Maximum green time while the other road is waiting |
| `GAP_SEC` | 3 s | Vehicle-free gap that ends a green phase |
| `YELLOW_SEC` | 3 s | Yellow time |
| `ALLRED_SEC` | 2 s | All-red time between phases |
| `FLASH_SEC` | 4 s | Minimum flashing time at start-up / after a fault |
| `FILTER_MS` | 50 ms | Sensor filter time (top level) |
| `CLK_HZ` | 12 000 000 | Board clock frequency |

### Design notes

- `MAX_GREEN` only applies while the other road has a vehicle waiting. If nobody is waiting, green can last longer
  than 20 s and the phase changes as soon as a vehicle arrives.
- The gap counter ticks once per second, aligned to the start of the state, so gap-out happens
  **2 to 3 s** after the last vehicle, not exactly 3 s.
- The longest a road can wait on red with a vehicle present is 27 s (2 + 20 + 3 + 2). The random test checks this bound.

## Repository structure

```
rtl/    traffic_improved.v        sensor_filter, traffic_ctrl (FSM + timers), traffic_top (board wrapper)
tb/     tb_c01 ... tb_c10         one self-checking testbench per scenario
        run_all.sh, run_case.do   Icarus Verilog / ModelSim runners
fpga/   traffic_improved.qpf/.qsf/.sdc   Quartus project, pin assignments, 12 MHz clock constraint
docs/   images/                   diagrams and waveforms used in this README
```

> Source comments and testbench messages are currently in Vietnamese (ASCII, no diacritics).

## Getting started

### Simulation

Every testbench uses a 1 ms clock period (`CLK_HZ = 1000`), so **one second of simulated time equals 1000 clock cycles**
and the ModelSim time axis can be read directly in seconds. The logic and all timing parameters are the same as on the board.

Run all cases with Icarus Verilog:

```sh
sh tb/run_all.sh
```

Run one case in ModelSim / Questa (from the `tb/` directory):

```
do run_case.do tb_c05_ca_hai_huong_co_xe
```

Each testbench prints `ok` / `FAIL` for every check and ends with `KET QUA: DAT` (pass) or `KET QUA: KHONG DAT` (fail).

### FPGA (Quartus Prime Lite)

1. Open `fpga/traffic_improved.qpf` (top-level entity: `traffic_top`, device `10M08SCM153C7G`).
2. Check the pins in **Assignments -> Pin Planner** (see the table below).
3. **Processing -> Start Compilation**, then program `output_files/traffic_improved.sof` with the Programmer.

If your board uses the 10M02 device, change `DEVICE` in the `.qsf` to `10M02SCM153C8G`.

### Board I/O (STEP-MAX10)

| Signal | Board item | Pin | Function |
|---|---|---|---|
| `clk` | 12 MHz clock | J5 | System clock |
| `key4_n` | KEY4 | J14 | Reset (active low) |
| `sw[0]` | SW1 | J12 | TA – vehicle on road A (ON = 1) |
| `sw[1]` | SW2 | H11 | TB – vehicle on road B (ON = 1) |
| `sw[2]` | SW3 | H12 | Fault mode (flashing red) |
| `rgb1_n[2:0]` | RGB LED1 (B,G,R) | D12, C14, C15 | Light A |
| `rgb2_n[2:0]` | RGB LED2 (B,G,R) | E14, E15, G15 | Light B |
| `led_n[7:0]` | LED1..LED8 | N15, N14, M14, M12, L15, K12, L11, K11 | LED1..LED7: state F, S0..S5 (one-hot); LED8: fault |

Yellow is produced by switching on the red and green channels together. The RGB LEDs are common-anode (active low).
The two RGB pin groups are swapped compared with the pin table in the board manual – this was found and fixed during testing on the board.

## Verification

| Case | Scenario | Result |
|---|---|---|
| `tb_c01_khoi_dong` | Start-up | Flashing red 4.00 s, all-red 2.00 s, then A green / B red |
| `tb_c02_khong_co_xe` | No vehicles anywhere | A stays green for 60 s (no pointless cycling) |
| `tb_c03_huong_B_co_xe` | Vehicle arrives on B | A turns yellow within 20 ms; yellow 3 s, all-red 2 s, then B green |
| `tb_c04_xanh_toi_thieu` | Other road already waiting | A and B each stay green exactly 5 s (`MIN_GREEN`) |
| `tb_c05_ca_hai_huong_co_xe` | Both roads always busy | Green 20 s each, yellow 3 s, all-red 2 s |
| `tb_c06_gap_out` | Vehicles thin out; last leaves at 8.2 s | A yields 2.80 s after the last vehicle |
| `tb_c07_xe_lien_tiep` | A vehicle every 2 s (gap < 3 s) | No gap-out; cut at `MAX_GREEN` = 20 s |
| `tb_c08_che_do_loi` | Fault switch while A is yellow | Flashing red immediately; a 1 s fault still flashes for 4 s; clean restart |
| `tb_c09_loc_nhieu` | Sensor glitch (top level) | 30 ms glitch ignored, 80 ms pulse accepted |
| `tb_c10_ngau_nhien_an_toan` | 1500 s of random sensors and faults | 0 safety violations, 0 illegal transitions, max red wait 27.00 s |

Random test (`tb_c10`) checks three properties during the whole run:

- the two roads are **never** allowed to go (green or yellow) at the same time;
- every state change follows the legal order (or goes to the flashing state on a fault);
- no road waits on red for more than 27 s.

In the reference run (1500 s, seed 20261030): 301 normal phase transitions and 27 entries into the flashing state,
0 safety violations, 0 illegal transitions, and a longest red wait of 25.16 s (road A) and 27.00 s (road B),
which matches the 27 s theoretical bound.

### Tested on the board

Quick check on STEP-MAX10 (all six steps passed):

1. Press KEY4: both lights flash red for about 4 s, then all-red, then A green / B red.
2. Wait 15 s with all switches off: A stays green.
3. Turn SW2 on: A yellow, all-red, then B green.
4. Turn SW2 off and SW1 on: B stays green at least 5 s, then yellow, all-red, A green.
5. Turn SW3 on: both lights flash red, LED1 and LED8 on.
6. Turn SW3 off: flashing continues, then all-red, then A green.

### Synthesis results (Quartus Prime Lite)

| Resource | Value |
|---|---|
| Total logic elements | 241 |
| Total registers | 147 |
| Total pins | 19 |
| Fmax (clk) | _TBD_ MHz (Slow 1200mV 85C model; the board clock is 12 MHz) |

## Limitations and ideas for future work

- No pedestrian phase (push button, walk light, crossing time).
- Yellow and all-red times are constants, not computed from speed limit and intersection width.
- No countdown display on the on-board 7-segment digits.
- The sensors are emulated with switches; a real design would use loop detectors or cameras.
- The testbenches are written in plain Verilog. A SystemVerilog version with constrained-random stimulus,
  assertions, functional coverage and a reference model would be a natural next step.

## Tools

Verilog HDL, Quartus Prime Lite, ModelSim (Intel FPGA edition), Icarus Verilog. Target: STEP-MAX10 board
(Intel MAX 10 `10M08SCM153C7G`, 12 MHz clock).

## References

- D. M. Harris and S. L. Harris, *Digital Design and Computer Architecture*, Morgan Kaufmann –
  the traffic light controller FSM exercise this project starts from.
- STEP-MAX10 hardware manual and schematic.
- Intel MAX 10 FPGA documentation and Quartus Prime Lite documentation.

## License

MIT – see [LICENSE](LICENSE).

## Author

[Thang Luu Quoc] – [luuquocthangg@gmail.com]
