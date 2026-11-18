proc rsc::read_libraries {} {
    global cfg
    set_thread_count $cfg(threads)
    define_corners SS FF
    foreach corner {SS FF} {
        foreach library $cfg(lib_$corner) {
            read_liberty -corner $corner $library
        }
    }
}

# Technology setup shared by placement/global routing and detailed routing.
proc rsc::load_design {} {
    global cfg
    read_libraries

    if {$cfg(stage) eq "grt"} {
        read_db $cfg(handoff_odb)
    } else {
        read_db [output_path grt.odb]
    }
    read_sdc [output_path input.sdc]
    set_units -time ps -capacitance fF -resistance kOhm -power mW
    source $cfg(rc)
}

proc rsc::configure_routing_layers {} {
    set_routing_layers -signal M1-M6 -clock M1-M6
    set_global_routing_layer_adjustment M1-M6 0.25
}

proc rsc::initialize_floorplan {} {
    global cfg
    ::initialize_floorplan \
        -utilization [expr {100 * $cfg(util)}] \
        -aspect_ratio 1 \
        -core_space 0.2 \
        -site asap7sc7p5t
    source $cfg(tracks)
}

proc rsc::mark_primary_clocks {} {
    foreach name $::cfg(clock_ports) {
        set port [[ord::get_db_block] findBTerm $name]
        set net [$port getNet]
        $net setSigType CLOCK
        set_dont_touch [get_nets [$net getName]]
    }
}
