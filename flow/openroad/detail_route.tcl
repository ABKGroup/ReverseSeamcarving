proc rsc::detail_route {} {
    read_guides [output_path route.guide]
    set_dont_touch [get_cells -hierarchical *]
    set_dont_touch [get_nets -hierarchical *]
    set_propagated_clock [all_clocks]
    detailed_route \
        -output_drc [output_path drc.rpt] \
        -output_guide_coverage [output_path guide_coverage.rpt] \
        -droute_end_iter 32 \
        -or_seed 1 \
        -verbose 1
    write_text drc_count.txt [drt::detailed_route_num_drvs]
    write_def [output_path routed.def]
    write_db [output_path routed.odb]
    extracted_timing
}
