#!/usr/bin/env python3
"""
Digital Emergency Power Management System (EPMS)
------------------------------------------------
Parses the VCD waveform produced by xsim (sim/waveforms/tb_epms_top.vcd)
and renders publication-quality timing diagrams for the project report.

Outputs (into docs/images/):
    waveform_seg1.png ... waveform_seg4.png   zoomed scenario windows
    waveform_full.png                         full-run overview

Run from the project root:   python tools/plot_waveforms.py
"""

from pathlib import Path
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ---------------------------------------------------------------- paths
ROOT = Path(__file__).resolve().parent.parent
VCD = ROOT / "sim" / "waveforms" / "tb_epms_top.vcd"
IMG = ROOT / "docs" / "images"
IMG.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------- VCD parser
def parse_vcd(path):
    """Return {signal_name: [(time_ps, value_int_or_None), ...]} for the
    top-level scope of the testbench."""
    ids = {}          # vcd id -> signal name (testbench top level only)
    series = {}
    scope = []
    t = 0
    in_defs = True

    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue

            if in_defs:
                if line.startswith("$scope"):
                    scope.append(line.split()[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var"):
                    p = line.split()
                    vid, name = p[3], p[4]
                    if scope == ["tb_epms_top"]:
                        ids[vid] = name
                        series[name] = []
                elif line.startswith("$enddefinitions"):
                    in_defs = False
                continue

            if line[0] == "#":
                t = int(line[1:])
            elif line[0] in "bB":
                val, vid = line[1:].split()
                if vid in ids:
                    v = int(val, 2) if set(val) <= {"0", "1"} else None
                    n = ids[vid]
                    if not series[n] or series[n][-1][1] != v:
                        series[n].append((t, v))
            elif line[0] in "01xzXZ":
                vid = line[1:]
                if vid in ids:
                    v = {"0": 0, "1": 1}.get(line[0])
                    n = ids[vid]
                    if not series[n] or series[n][-1][1] != v:
                        series[n].append((t, v))
    return series


def to_ns(t_ps):
    return t_ps / 1000.0


# ---------------------------------------------------------------- formatting
SRC_NAMES = {0: "MAINS", 1: "BATTERY", 2: "GENERATOR", 3: "BLACKOUT"}

# (signal, row label, kind)  kind: "d" digital 0/1, "b" bus
ROWS = [
    ("mains_ok",         "mains_ok",              "d"),
    ("gen_ready",        "gen_ready",             "d"),
    ("battery_low",      "battery_low",           "d"),
    ("battery_capacity", "battery_capacity [kW]", "b"),
    ("source_sel",       "source_sel",            "b"),
    ("available_power",  "available_power [kW]",  "b"),
    ("gen_request",      "gen_request",           "d"),
    ("load_on",          "load_on  L1..L6",       "b"),
    ("total_connected",  "connected load [kW]",   "b"),
    ("partial_shed",     "partial_shed",          "d"),
    ("buzzer",           "buzzer",                "d"),
]

DIG_FILLS = ["#2f6fbf", "#3f8ede", "#5ba0e8"]
BUS_EDGE = "#a86400"
BUS_FILL = "#f5b54a"


def fmt_bus(name, v):
    if v is None:
        return "X"
    if name == "source_sel":
        return SRC_NAMES.get(v, str(v))
    if name == "load_on":
        return format(v, "06b")
    return str(v)


def sample(series, name, t0, t1):
    """Return (xs, ys) stepped across [t0, t1]; y=None for unknown."""
    data = series.get(name, [(0, 0)])
    xs, ys = [], []
    for t_ps, v in data:
        t = to_ns(t_ps)
        if t > t1:
            break
        xs.append(t)
        ys.append(v)
    if not xs or xs[0] > t0:
        xs.insert(0, t0)
        ys.insert(0, ys[0] if ys else 0)
    xs.append(t1)
    ys.append(ys[-1])
    return xs, ys


def draw_row(ax, sig, label, kind, y, t0, t1, seg_min_frac=0.022):
    """Draw one waveform row inside band [y, y+1). Returns (y, ylabel)."""
    xs, ys = sample(None or sig_series, sig, t0, t1)

    if kind == "d":
        base = y + 0.06
        h = [base + (0.62 if v else 0.0) for v in ys]
        ax.fill_between(xs, base, h, step="post", color=DIG_FILLS[y % 3],
                        alpha=0.9, lw=0)
        ax.step(xs, [base] * len(xs), where="post", color="#20406e", lw=1.0)
        ax.step(xs, h, where="post", color="#20406e", lw=1.0)
        ax.axhline(y, color="0.82", lw=0.6)
        return (y + 0.4, label)
    else:
        vmax = max([v for _, v in sig_series.get(sig, [(0, 1)]) if v] or [1])
        base = y + 0.10
        h = [base + (0.70 * (v / vmax) if v is not None else 0.35) for v in ys]
        ax.fill_between(xs, base, h, step="post", color=BUS_FILL,
                        alpha=0.55, lw=0)
        ax.step(xs, h, where="post", color=BUS_EDGE, lw=1.3)
        lbl = label if vmax <= 1 else f"{label}  (0..{vmax})"

        # value text inside every sufficiently wide interval
        span = (t1 - t0) * seg_min_frac
        for k in range(len(xs) - 1):
            if xs[k + 1] - xs[k] >= span:
                ax.text((xs[k] + xs[k + 1]) / 2, h[k] + 0.03,
                        fmt_bus(sig, ys[k]), fontsize=6.8, ha="center",
                        va="bottom", color="#5a3a00", zorder=6)

        ax.axhline(y, color="0.82", lw=0.6)
        return (y + 0.4, lbl)


def annotate_events(ax, series, t0, t1, n_rows):
    """Vertical event markers with rotated labels above the top row.
    Labels close to each other are pushed into stacked lanes."""
    evs = []
    for t_ps, v in series.get("mains_ok", []):
        t = to_ns(t_ps)
        if t0 + 1 < t <= t1:
            evs.append((t, "MAINS RESTORED" if v else "MAINS FAILURE", "tab:green"))
    for t_ps, v in series.get("battery_low", []):
        t = to_ns(t_ps)
        if t0 + 1 < t <= t1:
            evs.append((t, "BATTERY LOW" if v else "BATTERY OK", "tab:red"))
    for t_ps, v in series.get("gen_request", []):
        t = to_ns(t_ps)
        if t0 + 1 < t <= t1:
            evs.append((t, "GEN REQUEST" if v else "GEN STOP", "tab:purple"))
    for t_ps, v in series.get("source_sel", []):
        t = to_ns(t_ps)
        if t0 + 1 < t <= t1:
            evs.append((t, f"SOURCE -> {SRC_NAMES.get(v, v)}", "tab:orange"))

    evs.sort(key=lambda e: e[0])
    min_gap = (t1 - t0) * 0.055
    lane, last_t = 0, -1e9
    for t, txt, col in evs:
        ax.axvline(t, color=col, ls="--", lw=0.9, alpha=0.8, zorder=1)
        if t - last_t < min_gap:
            lane = (lane + 1) % 3
        else:
            lane = 0
        last_t = t
        ax.text(t, n_rows + 1.25 - 0.42 * lane, txt, fontsize=6.6,
                rotation=90, ha="right", va="top", color=col,
                fontweight="bold", zorder=7)


def plot_window(series, t0, t1, fname, title):
    global sig_series
    sig_series = series

    n = len(ROWS)
    fig, ax = plt.subplots(figsize=(13.4, 9.2))

    ticks = []
    for i, (sig, label, kind) in enumerate(ROWS):
        ticks.append(draw_row(ax, sig, label, kind, n - i - 1, t0, t1))
    ax.set_yticks([t[0] for t in ticks])
    ax.set_yticklabels([t[1] for t in ticks], fontsize=8.5)

    annotate_events(ax, series, t0, t1, n)

    ax.set_xlim(t0, t1)
    ax.set_ylim(-0.15, n + 1.35)
    ax.set_xlabel("simulation time [ns]   (clock period = 10 ns)", fontsize=9)
    ax.set_title(title, fontsize=11, fontweight="bold", pad=34)
    ax.grid(axis="x", ls=":", alpha=0.4)
    fig.subplots_adjust(left=0.145, right=0.99, top=0.885, bottom=0.075)
    fig.savefig(IMG / fname, dpi=150)
    plt.close(fig)
    print(f"  written : docs/images/{fname}")


def plot_overview(series, t_end):
    global sig_series
    sig_series = series

    over = [("mains_ok", "mains_ok", "d"),
            ("gen_ready", "gen_ready", "d"),
            ("source_sel", "source_sel", "b"),
            ("gen_request", "gen_request", "d"),
            ("load_on", "load_on  L1..L6", "b"),
            ("total_connected", "connected load [kW]", "b"),
            ("buzzer", "buzzer", "d")]
    n = len(over)
    fig, ax = plt.subplots(figsize=(13.4, 6.0))

    ticks = []
    for i, (sig, label, kind) in enumerate(over):
        ticks.append(draw_row(ax, sig, label, kind, n - i - 1, 0, t_end,
                              seg_min_frac=0.012))
    ax.set_yticks([t[0] for t in ticks])
    ax.set_yticklabels([t[1] for t in ticks], fontsize=8.5)

    ax.set_xlim(0, t_end)
    ax.set_ylim(-0.15, n + 0.6)
    ax.set_xlabel("simulation time [ns]", fontsize=9)
    ax.set_title("EPMS - full emergency cycle overview "
                 "(testbench scenarios S1..S9)", fontsize=11, fontweight="bold")
    ax.grid(axis="x", ls=":", alpha=0.4)
    fig.subplots_adjust(left=0.145, right=0.99, top=0.92, bottom=0.08)
    fig.savefig(IMG / "waveform_full.png", dpi=150)
    plt.close(fig)
    print("  written : docs/images/waveform_full.png")


def main():
    if not VCD.exists():
        raise SystemExit(f"VCD not found: {VCD}\nRun sim/run_sim.bat first.")

    print(f"parsing {VCD.relative_to(ROOT)} ...")
    s = parse_vcd(VCD)

    t_end = to_ns(s["clk"][-1][0])
    print(f"simulation length : {t_end:.0f} ns\nrendering:")

    plot_window(s, 0, 1750,
                "waveform_seg1.png",
                "EPMS - Segment 1:  normal operation on mains  ->  mains failure, "
                "emergency operation on battery (loads L6, L5 shed)")

    plot_window(s, 1700, 2600,
                "waveform_seg2.png",
                "EPMS - Segment 2:  generator picks up the load  ->  mains restored "
                "(generator cool-down)  ->  3-cycle mains glitch is ignored")

    plot_window(s, 2550, 3600,
                "waveform_seg3.png",
                "EPMS - Segment 3:  second mains failure, battery 5 kW, battery_low "
                "derates to 2 kW  ->  generator timeout  ->  BLACKOUT")

    plot_window(s, 3550, t_end + 30,
                "waveform_seg4.png",
                "EPMS - Segment 4:  generator finally starts, loads rebuilt in "
                "priority order  ->  mains restored  ->  back to normal")

    plot_overview(s, t_end)


if __name__ == "__main__":
    main()
