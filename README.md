# Digital Emergency Power Management System (EPMS)

**Priority-Based Automatic Load Control During Limited Power Availability**

Verilog HDL · Verified with Xilinx Vivado 2025.2 (xsim) **and** Icarus Verilog 12.0

![Verilog](https://img.shields.io/badge/Verilog-2001-2ea44f)
![Vivado](https://img.shields.io/badge/Xilinx-Vivado%202025.2-000000)
![Tests](https://img.shields.io/badge/tests-97%20passing-brightgreen)
![Simulators](https://img.shields.io/badge/simulators-xsim%20%7C%20Icarus-blue)

A self-checking digital controller that monitors the available power from
MAINS / BATTERY / GENERATOR and automatically sheds the lowest-priority loads
whenever the supply cannot cover the demand, then re-energises them in strict
priority order as power returns.

![Block diagram](docs/images/block_diagram.png)

## Contents

```
emergency-power-management/
├── rtl/                       Verilog-2001, synthesizable source
│   ├── power_source_manager.v   source-select FSM (debounce, timeout, cool-down)
│   ├── priority_scheduler.v     strict-priority combinational allocator
│   ├── load_controller.v        fast shed / sequential restore
│   ├── alarm_unit.v             buzzer tone + 6 status LEDs
│   ├── seven_seg.v              hex → 7-segment decoder (x3 in top)
│   └── epms_top.v               top level (structural)
├── tb/                        self-checking testbenches
│   ├── tb_epms_top.v             9-scenario system regression (45 checks)
│   └── tb_priority_scheduler.v   exhaustive allocator sweep (52 checks)
├── sim/
│   ├── run_sim.bat               one-shot batch simulation (xvlog/xelab/xsim)
│   ├── run_xsim.tcl              xsim batch script (dumps VCD)
│   ├── run_xsim_unit.tcl         xsim batch script for the unit test
│   ├── run_system.log            captured system-regression console output
│   ├── run_unit.log              captured unit-test console output
│   └── waveforms/*.vcd           dumped waveforms
├── vivado/
│   └── create_project.tcl        creates the Vivado project with all sources
├── tools/
│   ├── plot_waveforms.py         VCD → report-ready waveform PNGs
│   ├── make_block_diagram.py     regenerates the block diagram PNG
│   └── strip_comments.py         strips // comments (EDA Playground copies)
├── edaplayground/
│   ├── design.v                  all 6 RTL modules in one file
│   ├── testbench.v               testbench + $dumpfile for the EPWave viewer
│   └── EDA_PLAYGROUND_GUIDE.md   step-by-step browser instructions
└── docs/
    ├── REPORT.md                 full project report
    └── images/                   block diagram + waveform figures
```

## Quick start

**Command line (batch simulation):**

```
sim\run_sim.bat
```

This compiles the RTL and both testbenches, runs both regressions, prints the
PASS/FAIL summary, saves the logs to `sim\run_system.log` and `sim\run_unit.log`
and dumps the waveforms to `sim\waveforms\*.vcd`.

Expected result (both regressions):

```
 CHECKS RUN : 45
 ERRORS     : 0
 RESULT     : **** ALL TESTS PASSED ****
```

**Run it in your browser (no Vivado install needed):**

1. Open [EDA Playground](https://www.edaplayground.com) → **Code**
2. Right pane ← `edaplayground/design.v`, left pane ← `edaplayground/testbench.v`
3. Language `SystemVerilog/Verilog`, simulator **Icarus Verilog 12.0**
4. Tick **Open EPWave after run** → **Run**

Full walkthrough, including the signal list to plot, is in
[`edaplayground/EDA_PLAYGROUND_GUIDE.md`](edaplayground/EDA_PLAYGROUND_GUIDE.md).

---

**Regenerate the report figures:**

```
python tools\plot_waveforms.py
python tools\make_block_diagram.py
```

**Vivado GUI:**

```
vivado -mode batch -source vivado\create_project.tcl
```

then **Flow Navigator → Simulation → Run Simulation → Run Behavioral
Simulation** and add the signals of `tb_epms_top` to the waveform viewer.

## What the design does

* **6 always-connected loads**, strict priority 1 (medical, 2 kW) …
  6 (HVAC fan, 3 kW), total 10 kW.
* **Sources:** MAINS 12 kW → BATTERY/inverter 0–8 kW → GENERATOR 10 kW →
  BLACKOUT.
* Mains input is **2-FF synchronised and debounced**; generator start is
  supervised by a **timeout**, generator stop by a **cool-down**.
* **Shedding is immediate** (1 clock); **restoration is sequenced**
  (one load per `LOAD_STEP` clocks — inrush limiting).
* `battery_low` **derates** the battery to 50 %.
* Audible alarm (intermittent beep on battery, continuous tone on blackout),
  6 status LEDs, and 3 seven-segment displays (source code + connected kW).

## Safety properties (continuously checked by the testbench)

* **P1** – the power consumed by the running loads never exceeds the power
  available from the active source.
* **P2** – the running loads are always a *prefix* of the priority list
  (a lower-priority load never runs while a higher-priority one is waiting).

See `docs/REPORT.md` for the full specification, architecture, block diagram,
detailed waveform interpretation and results tables.
