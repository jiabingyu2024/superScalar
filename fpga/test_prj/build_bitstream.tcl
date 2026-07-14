# Recreate the selected project, implement it, and write a bitstream.
# Usage:
#   vivado -mode batch -source fpga/test_prj/build_bitstream.tcl -tclargs srcSmoke 4

set script_dir [file normalize [file dirname [info script]]]
set mem_profile srcSmoke
set jobs 4
if {[info exists argv] && [llength $argv] >= 1} {
    set mem_profile [lindex $argv 0]
}
if {[info exists argv] && [llength $argv] >= 2} {
    set jobs [lindex $argv 1]
}

set argv [list $mem_profile]
source [file join $script_dir create_project.tcl]

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "write_bitstream Complete*" $impl_status]} {
    error "Implementation failed: $impl_status"
}

open_run impl_1
set report_dir [file normalize [file join $project_dir reports]]
file mkdir $report_dir
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir utilization_hier.rpt]

set bit_file [file normalize [file join $project_dir ${project_name}.runs impl_1 pynq_top.bit]]
puts "PYNQ_BITSTREAM_READY $bit_file"
puts "PYNQ_REPORT_DIR $report_dir"
close_project
