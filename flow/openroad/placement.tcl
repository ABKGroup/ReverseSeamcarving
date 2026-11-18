proc rsc::initial_placement {density} {
    global cfg
    set_dont_touch [get_cells -hierarchical *]
    set_dont_touch [get_nets -hierarchical *]
    global_placement \
        -random_seed $cfg(placement_seed) \
        -skip_io \
        -disable_pin_density_adjust \
        -density $density
}

proc rsc::main_placement {density} {
    global cfg
    set options [list \
        -random_seed $cfg(placement_seed) \
        -force_center_initial_place \
        -routability_driven \
        -disable_pin_density_adjust \
        -overflow $cfg(placement_overflow) \
        -density $density]
    global_placement {*}$options
}

proc rsc::legalize {} {
    set block [ord::get_db_block]
    # Partial screens guide global placement only; hard blockages remain.
    foreach blockage [$block getBlockages] {
        if {[$blockage getMaxDensity] > 0} {
            odb::dbBlockage_destroy $blockage
        }
    }
    set core [$block getCoreArea]
    set dbu [$block getDbUnitsPerMicron]
    set max_distance [expr {
        int(ceil(max([$core dx], [$core dy]) / double($dbu))) + 1
    }]
    detailed_placement \
        -use_diamond_legalizer \
        -max_displacement $max_distance
}

proc rsc::freeze_netlist {} {
    set_dont_touch [get_cells -hierarchical *]
    set_dont_touch [get_nets -hierarchical *]
}

proc rsc::freeze_placement {} {
    freeze_netlist
    foreach instance [[ord::get_db_block] getInsts] {
        $instance setPlacementStatus FIRM
    }
}
