# Connect imported constant nets to ASAP7 tie drivers before fanout repair.
proc rsc::map_constant_nets {} {
    set block [ord::get_db_block]
    set database [ord::get_db]
    set count 0
    foreach net [$block getNets] {
        set type [$net getSigType]
        if {$type ni {POWER GROUND}} {
            continue
        }
        set logical_pins {}
        foreach pin [$net getITerms] {
            if {[[$pin getMTerm] getSigType] ni {POWER GROUND}} {
                lappend logical_pins $pin
            }
        }
        set ports [$net getBTerms]
        if {[llength $logical_pins] == 0 && [llength $ports] == 0} {
            continue
        }

        if {$type eq "POWER"} {
            set master_name TIEHIx1_ASAP7_75t_R
            set output_pin H
        } else {
            set master_name TIELOx1_ASAP7_75t_R
            set output_pin L
        }
        $net setSigType SIGNAL
        foreach port $ports {
            $port setSigType SIGNAL
        }
        set master [$database findMaster $master_name]
        set instance [odb::dbInst_create \
            $block $master __literal_tie_${count}]
        [$instance findITerm $output_pin] connect $net
        incr count
    }
}
