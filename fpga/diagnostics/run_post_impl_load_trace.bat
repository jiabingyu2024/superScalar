@echo off
setlocal
cd /d %~dp0

call D:\AppMajor\xilinx\Vivado\2023.2\bin\xvlog.bat -sv --work xil_defaultlib --incr --relax post_impl_load_trace_tb.sv -log post_impl_load_trace_xvlog.log
if errorlevel 1 exit /b 1

call D:\AppMajor\xilinx\Vivado\2023.2\bin\xelab.bat --incr --debug typical --relax --mt 2 -L xil_defaultlib -L unisims_ver -L secureip --snapshot post_impl_load_trace xil_defaultlib.post_impl_load_trace_tb xil_defaultlib.glbl -log post_impl_load_trace_xelab.log
if errorlevel 1 exit /b 1

call D:\AppMajor\xilinx\Vivado\2023.2\bin\xsim.bat post_impl_load_trace -tclbatch post_impl_load_trace.tcl -log post_impl_load_trace.log
exit /b %errorlevel%
