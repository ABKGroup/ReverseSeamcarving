proc rsc::place_io {} {
    place_pins -hor_layers {M4 M6} -ver_layers {M3 M5}
    foreach terminal [[ord::get_db_block] getBTerms] {
        foreach pin [$terminal getBPins] {
            $pin setPlacementStatus FIRM
        }
    }
}
