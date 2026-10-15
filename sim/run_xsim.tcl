# ---------------------------------------------------------------------------
# xsim batch script : run the EPMS regression and dump a VCD waveform
# (invoked by sim\run_sim.bat)
# ---------------------------------------------------------------------------
open_vcd sim/waveforms/tb_epms_top.vcd
log_vcd  /tb_epms_top
run all
close_vcd
quit
