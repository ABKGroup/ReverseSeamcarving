# Edit these settings for the configuration to run.
set design jpeg
array set cfg {
    stage grt
    threads 8
    util 0.90
    width 0
    height 0
    pitch_x 300
    pitch_y 75
    delta 0.02
    placement_seed 1
    placement_overflow 0.05
}

set flow_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $flow_dir ../..]]
set pdk [file join $repo_root pdk ASAP7]

switch -- $design {
    jpeg {
        set cfg(top) jpeg_encoder
        set cfg(clock_ports) {clk}
    }
    ethmac {
        set cfg(top) ethmac
        set cfg(clock_ports) {wb_clk_i mtx_clk_pad_i mrx_clk_pad_i}
    }
    cva6_no_sram {
        set cfg(top) cva6
        set cfg(clock_ports) {clk_i}
    }
    swerv_no_macro {
        set cfg(top) swerv_wrapper
        set cfg(clock_ports) {clk}
    }
    mempool_tile_no_macro {
        set cfg(top) mempool_tile_wrap
        set cfg(clock_ports) {clk_i}
    }
    tpu {
        set cfg(top) tpu
        set cfg(clock_ports) {clk}
    }
}
set cfg(netlist) [file join $repo_root designs $design netlist.v]
set cfg(sdc) [file join $repo_root designs $design constraints.sdc]
set cfg(out) [file join $repo_root work $design \
    u$cfg(util)_w$cfg(width)_h$cfg(height)_p$cfg(pitch_x)x$cfg(pitch_y)_d$cfg(delta)_s$cfg(placement_seed)_o$cfg(placement_overflow)]
set cfg(handoff_odb) [file join $repo_root work handoffs $design handoff.odb]

set cfg(tech_lef) [file join $pdk lef asap7_tech_1x_201209.lef.gz]
set cfg(cell_lef) [file join $pdk lef asap7sc7p5t_28_R_1x_220121a.lef.gz]
set cfg(lib_FF) [list \
    [file join $pdk lib asap7sc7p5t_AO_RVT_FF_nldm_211120.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNH2V2X_RVT_FF_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNV2X_RVT_FF_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNV4X_RVT_FF_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_INVBUF_RVT_FF_nldm_220122.lib.gz] \
    [file join $pdk lib asap7sc7p5t_OA_RVT_FF_nldm_211120.lib.gz] \
    [file join $pdk lib asap7sc7p5t_SEQ_RVT_FF_nldm_220123.lib.gz] \
    [file join $pdk lib asap7sc7p5t_SIMPLE_RVT_FF_nldm_250407.lib.gz]]
set cfg(lib_SS) [list \
    [file join $pdk lib asap7sc7p5t_AO_RVT_SS_nldm_211120.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNH2V2X_RVT_SS_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNV2X_RVT_SS_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNV4X_RVT_SS_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_INVBUF_RVT_SS_nldm_220122.lib.gz] \
    [file join $pdk lib asap7sc7p5t_OA_RVT_SS_nldm_211120.lib.gz] \
    [file join $pdk lib asap7sc7p5t_SEQ_RVT_SS_nldm_220123.lib.gz] \
    [file join $pdk lib asap7sc7p5t_SIMPLE_RVT_SS_nldm_211120.lib.gz]]
set cfg(rc) [file join $flow_dir support rc.tcl]
set cfg(tracks) [file join $flow_dir support tracks.tcl]
set cfg(rcx) [file join $flow_dir support rcx.rules]
