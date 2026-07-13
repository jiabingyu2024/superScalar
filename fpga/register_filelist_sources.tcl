# Register RTL files listed by core.f/soc.f into an existing Vivado project.
# This intentionally performs no synthesis or implementation.
# Usage:
#   vivado -mode batch -source fpga/register_filelist_sources.tcl \
#          -tclargs srcWithMext

set profile srcWithMext
if {[info exists argv] && [llength $argv] >= 1} {
    set profile [lindex $argv 0]
}

set script_dir [file normalize [file dirname [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set project_file [file normalize [file join $script_dir build digital_twin_${profile} digital_twin.xpr]]

open_project $project_file
set added 0
foreach filelist_rel {scripts/filelists/core.f scripts/filelists/soc.f} {
    set filelist [file join $repo_dir $filelist_rel]
    set fh [open $filelist r]
    while {[gets $fh raw_line] >= 0} {
        set line [string trim [lindex [split $raw_line "#"] 0]]
        if {$line eq ""} {
            continue
        }
        foreach token [regexp -all -inline {\S+} $line] {
            if {[regexp {\.s?vh?$|\.sv$} $token]} {
                set source_file [file normalize [file join $repo_dir $token]]
                if {![file exists $source_file]} {
                    error "RTL source from $filelist_rel does not exist: $source_file"
                }
                if {[llength [get_files -quiet $source_file]] == 0} {
                    add_files -norecurse -fileset sources_1 $source_file
                    incr added
                }
                set_property file_type SystemVerilog [get_files $source_file]
            }
        }
    }
    close $fh
}
update_compile_order -fileset sources_1
puts "FILELIST_SOURCES_REGISTERED profile=$profile added=$added project=$project_file"
close_project
