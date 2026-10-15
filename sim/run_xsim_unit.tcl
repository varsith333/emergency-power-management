# ---------------------------------------------------------------------------
# xsim batch script : run the priority scheduler unit test
# ---------------------------------------------------------------------------
open_vcd sim/waveforms/tb_priority_scheduler.vcd
log_vcd  /tb_priority_scheduler
run all
close_vcd
quit
