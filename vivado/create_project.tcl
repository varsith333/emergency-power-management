# ---------------------------------------------------------------------------
# Digital Emergency Power Management System (EPMS)
# Create the Vivado project with all sources pre-added.
#
# Run this in the Vivado Tcl console (or: vivado -mode batch -source
# create_project.tcl) from the  emergency-power-management/vivado  folder.
#
# After it opens, use Flow Navigator:
#   Simulation > Run Simulation > Run Behavioral Simulation
# and add the signals of interest to the waveform viewer.
# ---------------------------------------------------------------------------

# Always create the project in the SAME directory as this script.
set proj_dir  [file dirname [file normalize [info script]]]
set proj_name "epms_project"
set proj_path [file join $proj_dir $proj_name]

create_project -force $proj_name $proj_path -part xc7z010clg400-1

# ---------------- RTL (synthesis sources) -------------------------------
set rtl_dir [file normalize [file join $proj_dir .. rtl]]
add_files -norecurse [list \
    [file join $rtl_dir power_source_manager.v] \
    [file join $rtl_dir priority_scheduler.v] \
    [file join $rtl_dir load_controller.v] \
    [file join $rtl_dir alarm_unit.v] \
    [file join $rtl_dir seven_seg.v] \
    [file join $rtl_dir epms_top.v] \
]

# ---------------- testbenches (simulation only) -------------------------
set tb_dir [file normalize [file join $proj_dir .. tb]]
add_files -fileset sim_1 -norecurse [list \
    [file join $tb_dir tb_epms_top.v] \
    [file join $tb_dir tb_priority_scheduler.v] \
]

# ---------------- tops ---------------------------------------------------
set_property top epms_top         [get_filesets sources_1]
set_property top tb_epms_top      [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------- simulation runtime ------------------------------------
# The testbench calls $finish at ~4.7 us, so 6 us covers the whole run.
set_property -name {xsim.simulate.runtime} -value {6us} -objects [get_filesets sim_1]

puts "=========================================================="
puts " EPMS Vivado project created at : $proj_path"
puts " Top (synthesis)  : epms_top"
puts " Top (simulation) : tb_epms_top"
puts ""
puts " Next steps:"
puts "   Flow Navigator > Simulation > Run Simulation"
puts "                     > Run Behavioral Simulation"
puts "=========================================================="
