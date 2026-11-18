proc rsc::build_clock_tree {} {
    unset_dont_touch [get_nets -hierarchical *]
    unset_dont_touch [get_cells -hierarchical *]
    clock_tree_synthesis \
        -buf_list {BUFx2_ASAP7_75t_R} \
        -root_buf BUFx2_ASAP7_75t_R \
        -tree_buf BUFx2_ASAP7_75t_R \
        -dont_use_dummy_load \
        -repair_clock_nets
    legalize
    set_propagated_clock [all_clocks]
}
