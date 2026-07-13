# Deep timing analysis from an existing routed checkpoint.
# Usage:
#   vivado -mode batch -source fpga/analyze_routed_timing.tcl -tclargs \
#       <project.xpr> <routed.dcp> <output_dir>

if {[llength $argv] < 3} {
    error "usage: analyze_routed_timing.tcl <project.xpr> <routed.dcp> <output_dir>"
}

set project_file [file normalize [lindex $argv 0]]
set checkpoint   [file normalize [lindex $argv 1]]
set output_dir   [file normalize [lindex $argv 2]]

open_project $project_file
open_checkpoint $checkpoint
file mkdir $output_dir

report_timing -delay_type max -slack_lesser_than 0 -max_paths 20000 -nworst 1 \
    -path_type summary -file [file join $output_dir setup_all_endpoints.rpt]
report_timing -delay_type max -slack_lesser_than 0 -max_paths 500 -nworst 1 \
    -path_type full_clock_expanded -file [file join $output_dir setup_worst_500.rpt]
report_timing -delay_type min -max_paths 200 -nworst 1 \
    -path_type full_clock_expanded -file [file join $output_dir hold_worst_200.rpt]

catch {
    report_timing -delay_type max -group async_default -slack_lesser_than 0 \
        -max_paths 1000 -nworst 1 -path_type summary \
        -file [file join $output_dir recovery_all_endpoints.rpt]
}
catch {
    report_high_fanout_nets -timing -load_types -max_nets 200 \
        -file [file join $output_dir high_fanout_200.rpt]
}
catch {
    report_control_sets -verbose -file [file join $output_dir control_sets.rpt]
}
catch {
    report_qor_assessment -file [file join $output_dir qor_assessment.rpt]
}
catch {
    report_design_analysis -timing -logic_level_distribution \
        -file [file join $output_dir design_analysis_timing.rpt]
}

puts "DEEP_TIMING_REPORT_DIR=$output_dir"
