@echo off
setlocal
cd /d %~dp0
call D:\AppMajor\xilinx\Vivado\2023.2\bin\xsim.bat post_impl_load_trace -tclbatch post_impl_load_trace.tcl -log post_impl_load_trace.log
exit /b %errorlevel%
