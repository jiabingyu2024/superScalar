# Report timing from an implementation checkpoint without rerunning synthesis.
# Usage:
#   vivado -mode batch -source fpga/report_checkpoint_timing.tcl -- \
#          <project.xpr> <checkpoint.dcp> <report_dir> <tag>

if {[llength $argv] < 4} {
    error "usage: report_checkpoint_timing.tcl <project.xpr> <checkpoint.dcp> <report_dir> <tag>"
}

set project_file [file normalize [lindex $argv 0]]
set checkpoint   [file normalize [lindex $argv 1]]
set report_dir   [file normalize [lindex $argv 2]]
set report_tag   [lindex $argv 3]

open_project $project_file
open_checkpoint $checkpoint
file mkdir $report_dir

report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_${report_tag}.rpt]
report_timing -delay_type max -max_paths 20 -path_type full_clock_expanded \
    -file [file join $report_dir timing_paths_setup_${report_tag}.rpt]
report_timing -delay_type min -max_paths 20 -path_type full_clock_expanded \
    -file [file join $report_dir timing_paths_hold_${report_tag}.rpt]

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $setup_paths] > 0} {
    puts "CHECKPOINT_WNS=[get_property SLACK [lindex $setup_paths 0]]"
}
