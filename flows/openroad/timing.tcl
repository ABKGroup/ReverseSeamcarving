proc rsc::timing_reports {stage} {
    report_wns -digits 6 > [output_path ${stage}_setup_wns.rpt]
    report_tns -digits 6 > [output_path ${stage}_setup_tns.rpt]
    report_wns -min -digits 6 > [output_path ${stage}_hold_wns.rpt]
    report_tns -min -digits 6 > [output_path ${stage}_hold_tns.rpt]
    report_checks -path_delay max -group_path_count 5 \
        > [output_path ${stage}_setup_paths.rpt]
    report_power -scene SS > [output_path ${stage}_power.rpt]
}

proc rsc::placement_timing {stage method} {
    estimate_parasitics $method
    timing_reports $stage
}

proc rsc::extracted_timing {} {
    define_process_corner -ext_model_index 0 ORD_NOMINAL_RC
    extract_parasitics -ext_model_file $::cfg(rcx)
    write_spef [output_path routed.spef]
    read_spef -corner SS [output_path routed.spef]
    read_spef -corner FF [output_path routed.spef]
    timing_reports routed
}
