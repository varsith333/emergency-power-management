# Running the EPMS Project on EDA Playground — Step by Step

**Verified locally on Icarus Verilog 12.0** (the exact simulator EDA Playground
uses): both files compile clean and the regression reports
`CHECKS RUN : 45, ERRORS : 0, RESULT : **** ALL TESTS PASSED ****`.
The generated `dump.vcd` contains 13 scopes / 178 signals, so EPWave can read it.

---

## 0. Why a single file each?

EDA Playground gives you **two panes only** — *Design* (right) and *Testbench*
(left). Your project is 6 RTL files + 2 testbenches, so the extra files are
merged into one per pane:

| EDA Playground pane | File in this folder | What it contains |
|--------------------|--------------------|------------------|
| **Design** (right) | `design.v` | all 6 RTL modules, in order |
| **Testbench** (left) | `testbench.v` | `tb_epms_top` + the `$dumpfile`/`$dumpvars` block EPWave needs |

EDA Playground compiles the **Design pane first, then the Testbench pane**, so
the order is already correct.

> The `tb_epms_top.v` you use in Vivado is identical to `testbench.v` **except**
> for one added `initial` block at the end that dumps the waveform. Nothing else
> was changed, so the results you get on EDA Playground are the same as in Vivado.

---

## 1. Open the site

1. Go to **<https://www.edaplayground.com>**.
2. Click **Code** (top menu) to open a fresh playground.
   A blank playground opens with two code panes and a settings bar on the left.

*(Logging in is optional for this project — see step 3.)*

---

## 2. Paste the two files

1. **Right pane = Design.** It may already contain example code.
   * Select all (`Ctrl` + `A`) and delete it.
   * Open `design.v` from this folder, copy **all** of it, paste it in.
2. **Left pane = Testbench.**
   * Select all (`Ctrl` + `A`) and delete it.
   * Open `testbench.v` from this folder, copy **all** of it, paste it in.

Do **not** paste the testbench into the design pane or vice-versa.

---

## 3. Choose the language

In the left settings bar, under **Languages & Libraries**:

1. **Testbench + Design** → choose **`SystemVerilog/Verilog`**.
   (Our code is Verilog-2001; this option compiles it correctly.)
2. **UVM / OVM** → leave as **`None`**.
3. **Other Libraries** → leave as **`None`**.

---

## 4. Choose the simulator

Under **Tools & Simulators**, pick **one** of these:

| Simulator | Login needed? | Notes |
|-----------|:-------------:|-------|
| **Icarus Verilog 12.0** | **No** | ✅ Recommended. Fast, free, fully verified for this project. |
| **Aldec Riviera Pro** | **No** | Commercial simulator, free to use on EDA Playground. Good second choice. |
| Siemens Questa / Synopsys VCS / Cadence Xcelium | **Yes** — validated account | Only if your institution gave you an approved EDA Playground account. |

**For most students: select `Icarus Verilog 12.0` and skip the login entirely.**

> Note: **Vivado xsim is not offered on EDA Playground** — it is not in their
> current simulator list. If you specifically need xsim, use your local Vivado
> install (`sim\run_sim.bat` or `vivado\create_project.tcl`). EDA Playground is
> for the browser-based/Icarus flow.

---

## 5. Enable the waveform viewer

Under **Tools & Simulators**, tick the checkbox:

- [x] **Open EPWave after run**

This makes the waveform viewer open in a new browser tab once the simulation
finishes. (This works because `testbench.v` contains the `$dumpfile` /
`$dumpvars` block — do not delete it.)

Two optional but useful checkboxes in the same area:

- [ ] **Download files after run** — gives you a `.zip` with the code, logs and
  the `dump.vcd`. Useful as evidence for your report.
- **Run Options → Verbose** — shows the full compile/run log.

---

## 6. Run it

Click the green **▶ Run** button (bottom-left of the settings bar), or press
`Ctrl` + `Enter`.

The first run takes ~10–20 seconds (the service boots a container and compiles).
Then three things happen:

1. **Console** (bottom of the screen) — your `$display` output appears.
2. **EPWave** opens in a **new tab** with the waveform.
3. If you ticked it, a **download** of the run directory starts.

---

## 7. What you should see in the console

Scroll to the bottom of the console. You must see:

```
=================================================================
 CHECKS RUN : 45
 ERRORS     : 0
 RESULT     : **** ALL TESTS PASSED ****
=================================================================
```

Above that, the nine scenarios print `[PASS]` lines, e.g.:

```
--- SCENARIO 2 : mains failure, emergency on battery -----------
[PASS] 845 ns : S2 source code (1=BATT) = 1
[PASS] 845 ns : S2 loads L1..L5 kept = 011111
```

If instead you see `RESULT : **** N TEST(S) FAILED ****`, something went wrong
with the paste — see **Troubleshooting** below.

---

## 8. View the waveform in EPWave

In the EPWave tab:

1. Click **Get Signals** (top-left).
2. In the scope tree, open **`tb_epms_top`**.
3. Select these and click **Append Selected**:
   - `mains_ok`, `gen_ready`, `battery_low`
   - `battery_capacity`, `source_sel`, `available_power`
   - `gen_request`, `load_on`, `total_connected`
   - `partial_shed`, `buzzer`
4. Use **Zoom Fit** (or `Ctrl`+`F`) to see the whole 4.675 µs run.
5. Use the **zoom in** / **zoom out** buttons (or `+` / `-`) to inspect the
   interesting windows:

| Window | What to look for |
|--------|------------------|
| ~0–700 ns | normal operation on mains, `load_on` staircase 000000 → 111111, `total_connected` 0 → 10 kW |
| ~690 ns | **mains failure** — `source_sel` → BATTERY, `gen_request` rises, `load_on` drops to `011111` |
| ~1700 ns | generator ready — `source_sel` → GENERATOR, loads rebuilt in priority order |
| ~2435 ns | 3-cycle mains glitch — **ignored**, nothing changes |
| ~2600–3400 ns | battery derate → `load_on` = `000001` (only medical), then **BLACKOUT** = `000000` |
| ~3355 ns | blackout — `available_power` = 0, `buzzer` continuous tone |

For the full-window overview and high-resolution annotated versions of these,
see `docs/images/waveform_seg1..4.png` and `waveform_full.png`.

---

## 9. Save and share the playground

1. Click **Save** (top-left, requires a free login — Google login is enough and
   gives you access to Icarus and Riviera).
2. Give it a name, e.g. `EPMS - Digital Emergency Power Management System`.
3. After saving you get a permanent link like:
   `https://www.edaplayground.com/x/XXXXXXX`
4. Tick **Share** to make it publicly viewable.

**Put that link in your report and paste it into your presentation** — it lets
your guide open your working design in a browser with one click, with no Vivado
install required. This is the single strongest piece of evidence for the
"Presentation / demonstration" rubric row.

> Tip: if you already ran it without logging in, log in first, then press
> **Save** — EDA Playground keeps your current code so nothing is lost.

---

## 10. Optional: also run the scheduler unit test on EDA Playground

The exhaustive allocator sweep is a separate testbench. Because a playground has
only one testbench pane, run it in a **second playground**:

1. Open a new playground.
2. **Design pane** → paste the same `design.v`.
3. **Testbench pane** → instead paste the contents of
   `../../tb/tb_priority_scheduler.v` (unchanged — it needs no `$dumpfile`).
4. Same settings: `SystemVerilog/Verilog`, `Icarus Verilog 12.0`.
5. Run. Expected at the bottom of the console:

```
 PRIORITY SCHEDULER UNIT TEST : checks=52 errors=0
 RESULT     : **** ALL TESTS PASSED ****
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `error: Unknown module type: epms_top` | RTL pasted into the **wrong** pane, or truncated | Paste `design.v` in the **right** pane, `testbench.v` in the **left** pane. Check the very last module in the design pane ends with `endmodule`. |
| `Unable to find the top module` / `No such file` | Empty pane or missing `module` keyword | Re-paste both files fully. |
| `Validation Error` / `User Validation Required` popup | You selected Questa, VCS or Xcelium without a validated account | Switch to **Icarus Verilog** or **Aldec Riviera Pro** — neither needs validation. |
| Console shows errors before the testbench runs | Vivado-only construct in the RTL | Should not happen — this exact file was verified on Icarus 12.0. Re-check the paste for corruption (e.g. smart-quotes). |
| `CHECKS RUN` missing / no `RESULT` line | `testbench.v` truncated during paste | Re-paste. The file must be ~309 lines and end with `endmodule`. |
| Run hangs / times out | Playground limit is 60 s and 100 MB | Our sim finishes in ~5 s of simulated time. If it hangs, the paste is wrong. |
| EPWave tab is empty | `$dumpfile`/`$dumpvars` block deleted, or checkbox not ticked | Re-paste `testbench.v` and tick **Open EPWave after run**. |
| Waveform tab does not open | Browser blocked the popup | Allow popups for `edaplayground.com`, then re-run. |

---

## File checklist

- [ ] `design.v` — 533 lines, 6 modules (`power_source_manager`, `priority_scheduler`,
      `load_controller`, `alarm_unit`, `seven_seg`, `epms_top`)
- [ ] `testbench.v` — 309 lines, `tb_epms_top` + `$dumpfile`/`$dumpvars`
- [ ] Both compile with **zero errors** on Icarus Verilog 12.0
- [ ] Console ends with `CHECKS RUN : 45 / ERRORS : 0 / ALL TESTS PASSED`
- [ ] EPWave opens with the waveform
- [ ] Playground saved and the share link recorded for the report
