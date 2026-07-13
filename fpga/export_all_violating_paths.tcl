# Export every setup path whose slack is negative from an implemented design.
# Usage:
#   vivado -mode batch -source fpga/export_all_violating_paths.tcl \
#          -tclargs srcWithMext 100000 iteration8

set profile srcWithMext
set max_paths 100000
set report_tag latest
if {[info exists argv] && [llength $argv] >= 1} {
    set profile [lindex $argv 0]
}
if {[info exists argv] && [llength $argv] >= 2} {
    set max_paths [lindex $argv 1]
}
if {[info exists argv] && [llength $argv] >= 3} {
    set report_tag [lindex $argv 2]
}

set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir build digital_twin_${profile}]]
set project_file [file join $project_dir digital_twin.xpr]
set report_dir [file normalize [file join $project_dir reports]]
file mkdir $report_dir

open_project $project_file
open_run impl_1

set raw_report [file join $report_dir ${report_tag}_all_violating_setup_paths.rpt]
if {![file exists $raw_report] || [file size $raw_report] == 0} {
    report_timing -setup -slack_lesser_than 0.0 \
        -max_paths $max_paths -nworst 1 -sort_by group -file $raw_report
}

set paths [get_timing_paths -setup -slack_lesser_than 0.0 \
    -max_paths $max_paths -nworst 1]
set csv_file [file join $report_dir ${report_tag}_all_violating_setup_paths.csv]
set summary_file [file join $report_dir ${report_tag}_all_violating_setup_paths_summary.txt]
set csv [open $csv_file w]
puts $csv "index,slack_ns,requirement_ns,datapath_delay_ns,logic_levels,startpoint_pin,endpoint_pin,path_group"

set index 0
foreach path $paths {
    incr index
    set slack [get_property SLACK $path]
    set requirement [get_property REQUIREMENT $path]
    set datapath_delay [get_property DATAPATH_DELAY $path]
    set logic_levels [get_property LOGIC_LEVELS $path]
    set startpoint [get_property STARTPOINT_PIN $path]
    set endpoint [get_property ENDPOINT_PIN $path]
    set path_group "setup"
    foreach value_name {startpoint endpoint path_group} {
        set value [set $value_name]
        set value [string map [list "\"" "\"\""] $value]
        set $value_name "\"$value\""
    }
    puts $csv "$index,$slack,$requirement,$datapath_delay,$logic_levels,$startpoint,$endpoint,$path_group"
}
close $csv

set summary [open $summary_file w]
puts $summary "profile=$profile"
puts $summary "report_tag=$report_tag"
puts $summary "slack_filter=slack<0.0ns"
puts $summary "nworst_per_endpoint=1"
puts $summary "max_paths=$max_paths"
puts $summary "exported_path_count=$index"
puts $summary "raw_report=$raw_report"
puts $summary "csv=$csv_file"
close $summary

puts "ALL_VIOLATING_PATHS_EXPORTED count=$index report=$raw_report csv=$csv_file"
close_project
