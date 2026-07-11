# Export one worst setup path for every failing endpoint from a routed DCP.
# This is a read-only timing query; it does not modify implementation state.

if {[llength $argv] != 2} {
    puts stderr "usage: vivado -mode batch -source export_all_setup_endpoints.tcl -tclargs <routed.dcp> <output.csv>"
    exit 2
}

set dcp_path [file normalize [lindex $argv 0]]
set csv_path [file normalize [lindex $argv 1]]

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

puts "EXPORT_ALL_SETUP_ENDPOINTS: opening $dcp_path"
open_checkpoint $dcp_path

# nworst=1 gives one representative (the worst path) per endpoint.  A larger
# nworst would enumerate alternative paths to the same endpoint and obscure
# endpoint coverage without changing the failing-endpoint count.
set paths [get_timing_paths -delay_type max -max_paths 100000 -nworst 1 \
    -slack_lesser_than 0 -sort_by slack]

set fh [open $csv_path w]
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

puts "EXPORT_ALL_SETUP_ENDPOINTS: exported $rank failing endpoints to $csv_path"
close_design
exit 0
