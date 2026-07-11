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

# Return a timing-path property without allowing a Vivado-version-specific
# missing property to abort the whole export.
proc safe_property {property object} {
    if {[catch {get_property $property $object} value]} {
        return ""
    }
    return $value
}

proc csv_quote {value} {
    set escaped [string map [list "\"" "\"\""] $value]
    return "\"$escaped\""
}

# A compact, machine-readable index lets later analysis cluster path families
# without scraping the human-oriented report_timing text.
proc export_path_csv {filename delay_type max_paths nworst args} {
    set query [list get_timing_paths -delay_type $delay_type \
        -max_paths $max_paths -nworst $nworst -sort_by slack]
    set query [concat $query $args]
    set paths [uplevel #0 $query]
    set fh [open $filename w]
    puts $fh "rank,slack_ns,requirement_ns,datapath_delay_ns,logic_levels,path_group,startpoint,end_point,start_clock,end_clock"
    set rank 0
    foreach path $paths {
        incr rank
        set values [list \
            $rank \
            [safe_property SLACK $path] \
            [safe_property REQUIREMENT $path] \
            [safe_property DATAPATH_DELAY $path] \
            [safe_property LOGIC_LEVELS $path] \
            [safe_property PATH_GROUP $path] \
            [safe_property STARTPOINT_PIN $path] \
            [safe_property ENDPOINT_PIN $path] \
            [safe_property STARTPOINT_CLOCK $path] \
            [safe_property ENDPOINT_CLOCK $path]]
        set quoted [list]
        foreach value $values {
            lappend quoted [csv_quote $value]
        }
        puts $fh [join $quoted ,]
    }
    close $fh
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
puts $metadata "design_mode=[get_property DESIGN_MODE [current_design]]"
puts $metadata "route_status=[get_property ROUTE_STATUS [current_design]]"
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
run_report setup_violations_top1000 [list report_timing \
    -delay_type max \
    -max_paths 1000 \
    -nworst 100 \
    -slack_lesser_than 0 \
    -sort_by group \
    -path_type full_clock_expanded \
    -input_pins \
    -file [file join $out_dir setup_violations_top1000.rpt]]
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
run_report utilization_flat [list report_utilization \
    -file [file join $out_dir utilization_flat.rpt]]
run_report route_status [list report_route_status \
    -file [file join $out_dir route_status.rpt]]
run_report clock_utilization [list report_clock_utilization \
    -file [file join $out_dir clock_utilization.rpt]]
run_report control_sets [list report_control_sets \
    -verbose \
    -file [file join $out_dir control_sets.rpt]]
run_report power [list report_power \
    -file [file join $out_dir power.rpt]]
run_report design_analysis_timing [list report_design_analysis \
    -timing \
    -file [file join $out_dir design_analysis_timing.rpt]]
# Do not invoke `report_design_analysis -congestion` here. Vivado 2023.2
# crashes with EXCEPTION_ACCESS_VIOLATION on this routed design instead of
# returning a Tcl error. Route status, timing analysis and QoR reports remain
# safe substitutes, and the crash log is archived separately as evidence.
run_report design_analysis_complexity [list report_design_analysis \
    -complexity \
    -hierarchical_depth 12 \
    -file [file join $out_dir design_analysis_complexity.rpt]]
run_report qor_assessment [list report_qor_assessment \
    -file [file join $out_dir qor_assessment.rpt]]
run_report qor_suggestions [list report_qor_suggestions \
    -file [file join $out_dir qor_suggestions.rpt]]
run_report exceptions_coverage [list report_exceptions \
    -coverage \
    -file [file join $out_dir exceptions_coverage.rpt]]
run_report methodology [list report_methodology \
    -file [file join $out_dir methodology.rpt]]
run_report drc [list report_drc \
    -file [file join $out_dir drc.rpt]]
run_report setup_paths_csv [list export_path_csv \
    [file join $out_dir setup_paths_top1000.csv] max 1000 100]
run_report setup_violations_csv [list export_path_csv \
    [file join $out_dir setup_violations_top1000.csv] max 1000 100 \
    -slack_lesser_than 0]
run_report hold_paths_csv [list export_path_csv \
    [file join $out_dir hold_paths_top500.csv] min 500 50]

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
