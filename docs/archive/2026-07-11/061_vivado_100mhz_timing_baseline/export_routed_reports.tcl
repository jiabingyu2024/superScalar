# Export analysis reports from an existing routed Vivado checkpoint.
# This script is read-only with respect to the checkpoint: it does not run
# synthesis, implementation, physical optimization, or bitstream generation.

if {[llength $argv] != 2} {
    puts stderr "usage: vivado -mode batch -source export_routed_reports.tcl -tclargs <routed.dcp> <output_dir>"
    exit 2
}

set dcp_path [file normalize [lindex $argv 0]]
set out_dir  [file normalize [lindex $argv 1]]
file mkdir $out_dir

set failures [list]

proc run_report {name command} {
    global failures
    puts "EXPORT: $name"
    if {[catch {uplevel #0 $command} message]} {
        puts stderr "EXPORT FAILED: $name: $message"
        lappend failures "$name: $message"
    }
}

puts "EXPORT: opening $dcp_path"
open_checkpoint $dcp_path

set metadata_file [file join $out_dir export_metadata.txt]
set metadata [open $metadata_file w]
puts $metadata "source_checkpoint=$dcp_path"
puts $metadata "exported_at=[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]"
puts $metadata "vivado_version=[version -short]"
puts $metadata "design=[current_design]"
puts $metadata "part=[get_property PART [current_design]]"
foreach clk [lsort [get_clocks -quiet]] {
    puts $metadata "clock=$clk period_ns=[get_property PERIOD $clk] waveform=[get_property WAVEFORM $clk]"
}
close $metadata

run_report clocks [list report_clocks \
    -file [file join $out_dir clocks.rpt]]
run_report clock_interaction [list report_clock_interaction \
    -delay_type min_max \
    -file [file join $out_dir clock_interaction.rpt]]
run_report cdc [list report_cdc \
    -details \
    -file [file join $out_dir cdc.rpt]]
run_report timing_summary [list report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 100 \
    -file [file join $out_dir timing_summary_max100.rpt]]
run_report setup_top200 [list report_timing \
    -delay_type max \
    -max_paths 200 \
    -nworst 20 \
    -sort_by group \
    -file [file join $out_dir setup_top200.rpt]]
run_report hold_top100 [list report_timing \
    -delay_type min \
    -max_paths 100 \
    -nworst 10 \
    -sort_by group \
    -file [file join $out_dir hold_top100.rpt]]
run_report high_fanout_nets [list report_high_fanout_nets \
    -timing \
    -max_nets 200 \
    -file [file join $out_dir high_fanout_nets.rpt]]
run_report check_timing [list check_timing \
    -verbose \
    -file [file join $out_dir check_timing.rpt]]
run_report utilization_hier [list report_utilization \
    -hierarchical \
    -hierarchical_depth 12 \
    -file [file join $out_dir utilization_hier.rpt]]
run_report methodology [list report_methodology \
    -file [file join $out_dir methodology.rpt]]
run_report drc [list report_drc \
    -file [file join $out_dir drc.rpt]]

if {[llength $failures] != 0} {
    set failure_file [open [file join $out_dir export_failures.txt] w]
    foreach failure $failures {
        puts $failure_file $failure
    }
    close $failure_file
    close_design
    exit 1
}

close_design
puts "EXPORT: completed successfully in $out_dir"
exit 0
