# Stage coordinator. Physical algorithms live in the sourced modules.
source [file join [file dirname [file normalize [info script]]] config.tcl]
set script_dir [file dirname [file normalize [info script]]]
foreach module {
    common platform seams density placement io cts timing
    global_route detail_route
} {
    source [file join $script_dir ${module}.tcl]
}

rsc::prepare_output
rsc::load_design
if {$::cfg(stage) eq "grt"} {
    rsc::initialize_floorplan
    rsc::configure_routing_layers
    rsc::apply_seams
    rsc::freeze_netlist
    set placement_density [rsc::placement_density]
    rsc::initial_placement $placement_density
    rsc::place_io
    rsc::main_placement $placement_density
    rsc::legalize
    rsc::placement_timing placed -placement
    rsc::build_clock_tree
    rsc::placement_timing postcts -placement
    rsc::freeze_placement
    rsc::global_route
} else {
    rsc::configure_routing_layers
    rsc::detail_route
}
exit
