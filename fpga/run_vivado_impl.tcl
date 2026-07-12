# Create the project and run synthesis plus routed implementation.
# Usage:
#   vivado -mode batch -source fpga/run_vivado_impl.tcl \
#          -tclargs srcWithMext 200.000

set runner_dir [file normalize [file dirname [info script]]]
set profile srcWithMext
set cpu_mhz 200.000
if {[llength $argv] >= 1} {
    set profile [lindex $argv 0]
}
if {[llength $argv] >= 2} {
    set cpu_mhz [lindex $argv 1]
}

set ::env(FPGA_MEM_PROFILE) $profile
set ::env(FPGA_CPU_CLK_MHZ) $cpu_mhz
set ::env(FPGA_PROJECT_TAG) "${profile}_${cpu_mhz}MHz"
set argv [list $profile]
source [file join $runner_dir create_vivado_project.tcl]

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis did not complete successfully: $synth_status"
}

launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "Implementation did not complete successfully: $impl_status"
}

open_run impl_1
set report_dir [file normalize [file join $project_dir reports]]
file mkdir $report_dir
report_timing_summary -delay_type max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_${cpu_mhz}MHz.rpt]
report_utilization -hierarchical -hierarchical_depth 12 \
    -file [file join $report_dir utilization_routed_${cpu_mhz}MHz.rpt]
report_clock_utilization \
    -file [file join $report_dir clock_utilization_${cpu_mhz}MHz.rpt]

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $setup_paths] > 0} {
    puts "ROUTED_WNS=[get_property SLACK [lindex $setup_paths 0]]"
}
puts "ROUTED_REPORT_DIR=$report_dir"
