@echo off
rem ===========================================================================
rem  Digital Emergency Power Management System - batch simulation script
rem  Compiles the RTL + testbenches with xvlog, elaborates with xelab and runs
rem  both regressions with xsim.  Waveforms are dumped as VCD into sim\waveforms
rem  and can be plotted with tools\plot_waveforms.py or opened in GTKWave.
rem ===========================================================================
setlocal
set XVBIN=D:\Xilinx\2025.2\Vivado\bin
set ROOT=%~dp0..
cd /d "%ROOT%"

if not exist sim\work     mkdir sim\work
if not exist sim\waveforms mkdir sim\waveforms

echo [1/6] xvlog : compiling RTL and testbenches ...
call "%XVBIN%\xvlog.bat" ^
    rtl\power_source_manager.v ^
    rtl\priority_scheduler.v ^
    rtl\load_controller.v ^
    rtl\alarm_unit.v ^
    rtl\seven_seg.v ^
    rtl\epms_top.v ^
    tb\tb_epms_top.v ^
    tb\tb_priority_scheduler.v
if errorlevel 1 goto :failed

echo [2/6] xelab : elaborating system testbench ...
call "%XVBIN%\xelab.bat" tb_epms_top -s epms_top_snap -debug typical
if errorlevel 1 goto :failed

echo [3/6] xsim  : running SYSTEM regression ...
call "%XVBIN%\xsim.bat" epms_top_snap -tclbatch sim/run_xsim.tcl > sim\run_system.log 2>&1
type sim\run_system.log
findstr /C:"RESULT" sim\run_system.log >nul
if errorlevel 1 goto :failed

echo [4/6] xelab : elaborating scheduler unit testbench ...
call "%XVBIN%\xelab.bat" tb_priority_scheduler -s sched_snap -debug typical
if errorlevel 1 goto :failed

echo [5/6] xsim  : running SCHEDULER unit regression ...
call "%XVBIN%\xsim.bat" sched_snap -tclbatch sim/run_xsim_unit.tcl > sim\run_unit.log 2>&1
type sim\run_unit.log
findstr /C:"RESULT" sim\run_unit.log >nul
if errorlevel 1 goto :failed

echo [6/6] done  : waveforms in sim\waveforms
exit /b 0

:failed
echo *** SIMULATION FAILED - see messages above ***
exit /b 1
