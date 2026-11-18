# Prepare an alternate unrepaired mapped netlist before floorplanning.
source $::env(ORD_CONFIG)
set script_dir [file dirname [file normalize [info script]]]
foreach module {common platform tie_cells} {
    source [file join $script_dir ${module}.tcl]
}

rsc::read_libraries
read_lef $cfg(tech_lef)
read_lef $cfg(cell_lef)
read_verilog $cfg(netlist)
link_design $cfg(top)
read_sdc [rsc::output_path input.sdc]
set_units -time ps -capacitance fF -resistance kOhm -power mW
source $cfg(rc)

rsc::map_constant_nets
repair_tie_fanout TIELOx1_ASAP7_75t_R/L
repair_tie_fanout TIEHIx1_ASAP7_75t_R/H
rsc::mark_primary_clocks
repair_design -pre_placement -verbose
foreach instance [[ord::get_db_block] getInsts] {
    $instance setPlacementStatus NONE
}
write_db [rsc::output_path handoff.odb]
write_verilog [rsc::output_path netlist.v]
exit
