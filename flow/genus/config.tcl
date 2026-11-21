# This script was written and developed by ABKGroup students at UCSD. However, the underlying commands and reports are copyrighted by Cadence.
# We thank Cadence for granting permission to share our research to help promote and foster the next generation of innovators.

set flow_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $flow_dir ../..]]
set pdk [file join $repo_root pdk ASAP7]
set synth(top) jpeg_encoder
set synth(threads) 8
set synth(rtl_files) {}
set synth(include_dirs) {}
set synth(defines) {}
set synth(sdc) [file join $repo_root designs jpeg constraints.sdc]
set synth(out) [file join $repo_root work genus jpeg]

# TT RVT NLDM libraries used by the original synthesis flow.
set synth(libraries) [list \
    [file join $pdk lib asap7sc7p5t_AO_RVT_TT_nldm_211120.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNH2V2X_RVT_TT_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNV2X_RVT_TT_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_DFFHQNV4X_RVT_TT_nldm_FAKE.lib.gz] \
    [file join $pdk lib asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib.gz] \
    [file join $pdk lib asap7sc7p5t_OA_RVT_TT_nldm_211120.lib.gz] \
    [file join $pdk lib asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib.gz] \
    [file join $pdk lib asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib.gz]]
