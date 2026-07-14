# Program the first connected xc7z020 device over JTAG.
# Usage:
#   vivado -mode batch -source fpga/test_prj/program_board.tcl -tclargs srcSmoke

set script_dir [file normalize [file dirname [info script]]]
set mem_profile srcSmoke
if {[info exists argv] && [llength $argv] >= 1} {
    set mem_profile [lindex $argv 0]
}

set bit_file [file normalize [file join $script_dir build $mem_profile \
    pynq_superscalar.runs impl_1 pynq_top.bit]]
if {![file exists $bit_file]} {
    error "Bitstream not found: $bit_file"
}

open_hw_manager
connect_hw_server
open_hw_target
set devices [get_hw_devices -quiet -filter {PART =~ "xc7z020*"}]
if {[llength $devices] == 0} {
    error "No xc7z020 device found. Check PYNQ-Z2 power, PROG/JTAG mode, and USB cable."
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device
puts "PYNQ_PROGRAMMED device=$device bitstream=$bit_file"
close_hw_manager
