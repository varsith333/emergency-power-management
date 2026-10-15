#!/usr/bin/env python3
"""
Digital Emergency Power Management System (EPMS)
------------------------------------------------
Generates the system block diagram used in the project report.
Output: docs/images/block_diagram.png

Run from the project root:   python tools/make_block_diagram.py
"""

from pathlib import Path
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

ROOT = Path(__file__).resolve().parent.parent
IMG = ROOT / "docs" / "images"
IMG.mkdir(parents=True, exist_ok=True)

fig, ax = plt.subplots(figsize=(15.5, 9.0))
ax.set_xlim(0, 15.5)
ax.set_ylim(0, 9.0)
ax.axis("off")


def box(x, y, w, h, text, fc="#eef3fb", ec="#26456e", fs=8.2, weight="normal",
        tc="#10233d", mono=False):
    p = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.045,rounding_size=0.10",
                       linewidth=1.3, edgecolor=ec, facecolor=fc, zorder=3)
    ax.add_patch(p)
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs,
            color=tc, fontweight=weight, zorder=4,
            family="monospace" if mono else "sans-serif")
    return (x, y, w, h)


def arrow(p1, p2, label="", color="#26456e", ls="-", rad=0.0, fs=7.2,
          lx=None, ly=None, lw=1.4):
    a = FancyArrowPatch(p1, p2, arrowstyle="-|>", mutation_scale=13,
                        color=color, lw=lw, linestyle=ls,
                        connectionstyle=f"arc3,rad={rad}", zorder=2)
    ax.add_patch(a)
    if label:
        mx = lx if lx is not None else (p1[0] + p2[0]) / 2
        my = ly if ly is not None else (p1[1] + p2[1]) / 2
        ax.text(mx, my, label, fontsize=fs, color=color, ha="center",
                va="center", backgroundcolor="white", zorder=5)


# ---------------------------------------------------------------- title
ax.text(7.75, 8.75, "DIGITAL EMERGENCY POWER MANAGEMENT SYSTEM (EPMS)\n"
        "Priority based automatic load control during limited power availability",
        ha="center", va="center", fontsize=13, fontweight="bold", color="#10233d")
ax.text(7.75, 8.28, "top module: epms_top   |   6 loads, strict priority 1..6   |   "
        "sources: MAINS -> BATTERY/INVERTER -> GENERATOR",
        ha="center", va="center", fontsize=8.6, color="#44597a")

# ---------------------------------------------------------------- power sources
ax.text(1.65, 7.85, "POWER  ENVIRONMENT", ha="center", fontsize=9,
        fontweight="bold", color="#7a4a00")
mains = box(0.30, 6.85, 2.75, 0.85, "MAINS 230 V AC\n(utility grid)", fc="#fdf1dd",
            ec="#a86400")
batt = box(0.30, 5.75, 2.75, 0.85, "BATTERY + INVERTER\n(capacity 0..8 kW)", fc="#fdf1dd",
           ec="#a86400")
gen = box(0.30, 4.65, 2.75, 0.85, "DIESEL GENERATOR\n(auto-start, 10 kW)", fc="#fdf1dd",
          ec="#a86400")
sens = box(0.30, 3.05, 2.75, 1.25,
           "SENSORS / METERING\nmains_ok   gen_ready\nbattery_low\nbattery_capacity[7:0]",
           fc="#fff8ec", ec="#a86400", fs=7.8, mono=True)

# ---------------------------------------------------------------- controller
ctrl = box(3.85, 2.35, 8.05, 5.55, "", fc="#f4f7fc", ec="#26456e")
ax.text(7.875, 7.62, "epms_top  -  DIGITAL CONTROLLER  (clk, rst_n)",
        ha="center", va="center", fontsize=9.6, fontweight="bold", color="#10233d")

psm = box(4.15, 5.95, 3.55, 1.35,
          "1)  power_source_manager\nsource-select FSM  (Moore)\n"
          "MAIN> BATT> GEN> BLACK\n2FF sync + debounce + timers",
          fc="#e8f0fb", ec="#26456e", fs=7.6, mono=True)
sched = box(4.15, 4.30, 3.55, 1.25,
            "2)  priority_scheduler\nstrict-priority allocator\n"
            "grant[5:0] = prefix of L1..L6",
            fc="#e8f0fb", ec="#26456e", fs=7.6, mono=True)
lctl = box(4.15, 2.65, 3.55, 1.25,
           "3)  load_controller\nfast shed (1 clk) / sequential\n"
           "restore (LOAD_STEP, inrush limit)",
           fc="#e8f0fb", ec="#26456e", fs=7.6, mono=True)
alarm = box(8.20, 5.95, 3.40, 1.35,
            "4)  alarm_unit\nbuzzer tone (beep / continuous)\n"
            "6 status LEDs",
            fc="#fdeaea", ec="#8c2f2f", fs=7.6, mono=True)
disp = box(8.20, 4.30, 3.40, 1.25,
           "5)  seven_seg  x3\nsource code + connected\nload in kW (tens/ones)",
           fc="#eafaf0", ec="#1f6b3d", fs=7.6, mono=True)
mon = box(8.20, 2.65, 3.40, 1.25,
          "MONITORING OUTPUTS\navailable_power[7:0]\n"
          "total_connected[7:0]\npartial_shed / emergency",
          fc="#f2f2f2", ec="#555555", fs=7.6, mono=True)

# ---------------------------------------------------------------- load bank
ax.text(13.75, 7.85, "LOAD BANK  (always connected)", ha="center", fontsize=9,
        fontweight="bold", color="#7a4a00")
loads = box(12.45, 2.95, 2.65, 4.55,
            "CONTACTORS  K1..K6\n(load_on[5:0])\n\n"
            "L1  Medical / Life Support\n      2 kW   prio 1\n"
            "L2  Control & Comm.\n      1 kW   prio 2\n"
            "L3  Emergency Lighting\n      1 kW   prio 3\n"
            "L4  Security System\n      1 kW   prio 4\n"
            "L5  Water Pump\n      2 kW   prio 5\n"
            "L6  HVAC / Ventilation\n      3 kW   prio 6\n"
            "--------------------\nTOTAL  10 kW",
            fc="#fdf1dd", ec="#a86400", fs=7.4, mono=True)

# ---------------------------------------------------------------- arrows
# power flow : sources -> controller -> loads
arrow((3.05, 7.28), (4.15, 6.90), rad=-0.06)
arrow((3.05, 6.18), (4.15, 6.62), rad=0.05)
arrow((3.05, 5.08), (4.15, 6.35), rad=0.10)
arrow((3.05, 3.68), (4.15, 6.10), rad=0.14, label="sense signals",
      lx=3.55, ly=4.75, ls="--", lw=1.1)
arrow((7.70, 6.62), (8.20, 6.62), label="source_sel[1:0]", ly=6.98, fs=6.9)
arrow((7.70, 4.92), (8.20, 4.92), label="partial_shed", ly=4.55, fs=6.9)
arrow((7.70, 3.27), (8.20, 3.27), label="metrics", ly=3.62, fs=6.9)
arrow((11.60, 5.00), (12.45, 5.70), label="load_on[5:0]", lx=12.02, ly=6.35, fs=6.9)
arrow((11.60, 6.30), (12.45, 6.55), label="gen_request", lx=12.02, ly=7.05, fs=6.9,
      color="#8c2f2f")

# internal data flow
arrow((5.92, 5.95), (5.92, 5.55), label="available_power[7:0]", lx=7.05, ly=5.75, fs=6.9)
arrow((5.92, 4.30), (5.92, 3.90), label="grant[5:0]", lx=6.75, ly=4.10, fs=6.9)
arrow((5.40, 6.10), (8.20, 4.55), rad=-0.12, ls="--", lw=1.0)
arrow((5.92, 5.20), (5.92, 3.40), ls=":", lw=0.9, color="#777777")

# ---------------------------------------------------------------- legend note
ax.text(0.30, 1.95,
        "OPERATION:\n"
        "  - available_power < total demand  ->  lowest priority loads are shed immediately (safety first)\n"
        "  - power returns  ->  loads are re-energised ONE AT A TIME in strict priority order (inrush limiting)\n"
        "  - mains failure is debounced, generator start is supervised by a timeout, generator stop by a cool-down\n"
        "  - always-valid safety property checked by the testbench:  sum(demands of running loads) <= available_power",
        fontsize=8.3, color="#243b57", family="monospace", va="top")

ax.text(0.30, 0.55,
        "SAFETY RULES (verified in simulation):\n"
        "  P1  connected load never exceeds the available power\n"
        "  P2  running loads are always a prefix of the priority list (L1 is never shed while L2 runs)",
        fontsize=8.3, color="#8c2f2f", family="monospace", va="top")

fig.tight_layout()
fig.savefig(IMG / "block_diagram.png", dpi=150)
print("written : docs/images/block_diagram.png")
