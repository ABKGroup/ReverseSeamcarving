# Reverse Seamcarving

Reverse seamcarving (RSC) redistributes placement density to create routing channels
between denser blocks of cells. This repository provides the OpenROAD flow,
the repaired mapped netlists used by that flow, and OpenROAD measurement data
for reviewing the experiments.

The baseline and seamcarved configurations use the same repaired netlist,
floorplan utilization, and placement/routing settings. Seam geometry and the
requested utilization increment within the blocks distinguish the carved cases.

## Repository contents

| Path | Contents |
| --- | --- |
| `flow/openroad/flow.tcl` | Stage coordinator |
| `flow/openroad/config.tcl` | Portable design, technology, and experiment configuration |
| `flow/openroad/build_handoff.tcl` | Import a released repaired netlist into OpenDB |
| `flow/openroad/preprocess.tcl` | Original constant-net mapping, tie-fanout repair, and pre-floorplan repair procedure |
| `flow/openroad/support/` | RC, track, and extraction support used in the experiments |
| `pdk/ASAP7/` | Selected RVT NLDM Liberty and gzipped LEF files used by the flow |
| `designs/` | Six repaired OpenROAD Verilog netlists and their SDCs |
| `flow/genus/synthesize.tcl` | Genus synthesis driver used to create the mapped inputs |
| `data/` | OpenROAD DOE definitions, per-run measurements, and summary CSVs |

## Flow modules

```text
flow/openroad/
├── flow.tcl             Stage ordering and GRT/DRT entry point
├── config.tcl           User parameters and design/technology paths
├── common.tcl           Output-path and text-file helpers
├── platform.tcl         Libraries, design import, floorplan, routing layers
├── seams.tcl            Seam intervals, disjoint rectangles, density balance
├── density.tcl          Blockage-adjusted global-placement target
├── io.tcl               IO pin placement
├── placement.tcl        Initial/main placement and legalization
├── cts.tcl              Clock-tree construction
├── timing.tcl           Estimated/extracted timing reports
├── global_route.tcl     Global routing and checkpoint output
├── detail_route.tcl     Detailed routing from the saved checkpoint
├── build_handoff.tcl    Reconstruct an input ODB from repaired Verilog
├── preprocess.tcl       Optional preprocessing of an unrepaired input
├── tie_cells.tcl        Constant-net mapping onto tie drivers
└── support/             RC, tracks, and extraction rules
```

`seams.tcl` owns the seam geometry and block-density calculation. Placement,
clock-tree construction, and routing use that geometry through the stage
coordinator. Detailed routing loads the saved global-route checkpoint.

## Designs

| Identifier | Top module | Description |
| --- | --- | --- |
| `ethmac` | `ethmac` | Ethernet MAC |
| `jpeg` | `jpeg_encoder` | JPEG encoder |
| `cva6_no_sram` | `cva6` | Macro-free CVA6 variant |
| `swerv_no_macro` | `swerv_wrapper` | Macro-free SweRV variant |
| `mempool_tile_no_macro` | `mempool_tile_wrap` | Macro-free MemPool tile variant |
| `tpu` | `tpu` | TPU design |

Each `designs/<identifier>/` directory contains `netlist.v` and `constraints.sdc`. These Verilog files are the frozen OpenROAD handoffs
**after pre-floorplan repair and before placement or CTS**. The preprocessing
maps constant nets onto ASAP7 tie cells, repairs tie-cell fanout, and runs
`repair_design -pre_placement`, allowing signal buffering and cell resizing.
Baseline and RSC share this resulting netlist. Existing synthesis buffers remain.

The data contains OpenROAD results. The `flow/genus/` directory contains the synthesis
driver only. No Genus-only mapped netlists or Innovus place-and-route flow are
included.

## OpenROAD flow

The flow performs the following stages.

1. Import the repaired netlist and create a floorplan from its cell area.
2. Generate vertical and horizontal seams on the legal site/row grid.
3. Run initial placement with `-skip_io`.
4. Assign IO pins and fix their locations.
5. Run fresh routability-driven placement with the seams applied.
6. Remove partial density screens for detailed legalization and legalize cells.
   Hard blockages remain.
7. Build the clock tree and legalize its buffers.
8. Run global routing and save its OpenDB checkpoint and routing guides.
9. Restore that checkpoint for detailed routing, followed by extraction and
   timing reports.

The placement-stage density screens shape the global placement. Their partial
constraints are removed by the existing legalization procedure, so the final
placement can fill part of the requested channels. This behavior matches the
saved experimental flow.

The signal netlist stays fixed after preprocessing. CTS uses
`BUFx2_ASAP7_75t_R` buffers and `-repair_clock_nets`. There is no post-CTS
`repair_timing` step. Clock-buffer insertion is enabled during CTS.

Signals and clocks use M1--M6. Global routing applies a 25% layer-capacity
reduction, allows residual congestion, and uses a congestion-iteration budget
of 50. Detailed routing uses a limit of 32 and restores the saved global-route
guides. Clean DRT summary entries have zero reported violations.

### Seam parameters

`U` is the floorplan utilization and `Delta` is an additive utilization increment
for the regions between seams. Both are fractions. For example, `U=0.90` and
`Delta=0.02` request 92% block utilization.

For seam-area fraction `f`, the requested density inside the seams is

```text
seam_density = [U - (1 - f) * (U + Delta)] / f
```

The implementation computes `f` from the actual clipped seam rectangles,
accounting for intersections once. It uses rounded percentage density screens,
or hard blockages when the requested seam density falls below 5%. Generated
rectangles and densities are recorded in `seams.txt`.

Widths and horizontal pitch are specified in sites, with 0.054 micrometers per
site. Heights and vertical pitch are specified in rows, with 0.270 micrometers
per row. A pitch of `240/60` therefore means 240 sites in X and 60 rows in Y.
Zero seam width and height select the baseline.

The seam procedure balances nominal cell area between blocks and seams, then
rounds the requested seam utilization to the native blockage-density setting.
A requested seam utilization below 5% uses a hard placement blockage. Partial
density screens guide global placement and are removed before detailed
placement. Hard placement blockages remain. The selected density, seam area,
and rectangles are written to `seams.txt`.

The flow performs initial skip-IO placement, places IO pins, restarts main
routability-driven placement, legalizes, inserts a clock tree, and legalizes
again. The signal netlist retains its original instances and cell masters through
these stages. CTS is the only permitted source of new cells after preprocessing.
GRT uses M1--M6 with a 25% capacity reduction and up to 50 congestion iterations.
DRT restores the saved guides and database and uses an end-iteration limit of
32. It runs pin access as part of native detailed routing. Placement and CTS
are completed before either routing stage.

## Running an individual configuration

The experiments use OpenROAD commit
`e2820c8efda9ccf9949ec439456f699615b0dc47`. The flow reads the bundled
technology files through explicit paths in `flow/openroad/config.tcl`.

Edit `design` and the `cfg` settings in that file for the desired case. For
example, the following settings select JPEG at 90% utilization with vertical
seam width 15 sites, horizontal seam height 2 rows, paired pitch 260/65,
and block-utilization increment +3%.

```tcl
set design jpeg
array set cfg {
    stage grt
    threads 8
    util 0.90
    width 15
    height 2
    pitch_x 260
    pitch_y 65
    delta 0.03
    placement_seed 1
    placement_overflow 0.05
}
```

From the repository root, reconstruct the repaired input checkpoint once for
the selected design, then run placement, CTS, and global routing.

```bash
openroad -exit flow/openroad/build_handoff.tcl
openroad -exit flow/openroad/flow.tcl
```

For detailed routing, change `stage` to `detail` in the same configuration
and invoke the flow again. It restores `grt.odb` and `route.guide` from the
same output directory.

```bash
openroad -exit flow/openroad/flow.tcl
```

For the baseline, set `width` and `height` to zero. Keep the same utilization,
placement seed, and overflow target. Output paths are generated from these
configuration values under `work/`.

### OpenROAD settings

| Setting | Meaning |
| --- | --- |
| `design` | Released design identifier |
| `cfg(stage)` | `grt` or `detail` |
| `cfg(threads)` | Threads per OpenROAD process |
| `cfg(util)` | Floorplan utilization as a fraction |
| `cfg(width)`, `cfg(height)` | Vertical seam width in sites and horizontal seam height in rows |
| `cfg(pitch_x)`, `cfg(pitch_y)` | Paired X pitch in sites and Y pitch in rows |
| `cfg(delta)` | Additive block-utilization increment |
| `cfg(placement_seed)` | Global placement random seed |
| `cfg(placement_overflow)` | Main-placement stopping overflow target |
| `cfg(netlist)`, `cfg(sdc)` | Input Verilog and constraints paths |
| `cfg(out)` | Output directory for the physical configuration |
| `cfg(handoff_odb)` | Repaired input checkpoint |

`preprocess.tcl` prepares an alternate unrepaired mapped input. Set the
`cfg(netlist)`, `cfg(sdc)`, and `cfg(out)` paths in `config.tcl` for that input
and a dedicated output directory, then run
`openroad -exit flow/openroad/preprocess.tcl`. It writes the repaired
`netlist.v` and `handoff.odb` there. Point `cfg(handoff_odb)` at the resulting
checkpoint for subsequent physical runs.

## Experimental coverage

Utilizations 90%, 91%, 92%, and 93% are evaluated separately. The widened grid
covers JPEG, ethmac, and TPU.

| Parameter | Original grid | Widened grid |
| --- | --- | --- |
| Block-utilization increment | +2%, +4%, +6% | +1%, +2%, +3%, +4%, +5%, +6% |
| Paired pitch, sites/rows | 280/70, 300/75, 320/80 | 240/60, 260/65, 280/70, 300/75, 320/80, 360/90 |
| Vertical width, sites | 10, 15 | 10, 15 |
| Horizontal height, rows | 2, 3 | 2, 3 |

Five global-placement seeds use the same nominal SDC. Selected configurations
receive detailed routing from their saved GRT handoffs. Single-axis controls
are retained in the data with their corresponding `kind`. The overflow
experiment repeats the widened grid at main-placement stopping targets 0.15
and 0.20. Its latest selection policy denoises five configurations and routes
three, each with five seeds, plus the baseline. That experiment remains a
partial snapshot exported on November 18, 2026.

## Results and CSV definitions

| File | Contents |
| --- | --- |
| `data/design_statistics.csv` | Repaired pre-CTS instance, logical-net, IO, and cell-area counts |
| `data/doe.csv` | Planned configurations for the original, widened, and overflow experiments |
| `data/openroad_measurements.csv` | Available per-configuration/per-seed GRT and DRT measurements and completion status |
| `data/openroad_summary.csv` | Best measured configurations per design, utilization, overflow, and routing stage |

Planned configurations and measurement rows have different purposes. A row in
`doe.csv` identifies the intended experiment. A measurement row records an
observed saved result. Identical control configurations are reused across the
original and widened grids and appear once in the measurement data. Known interrupted ethmac baseline
attempts are marked `incomplete`.

The summary minimizes configuration-median wirelength over the eligible
completed samples. It compares the RSC median against the median available
baseline at the same design, utilization, overflow target, and routing stage.
An `rwl_ratio` below 1 indicates improvement. `improvement_pct` is
`100 * (1 - rwl_ratio)`. Baseline and RSC sample counts identify partial coverage.
Summary rows with RSC measurements but no baseline retain their absolute WL and
leave the ratio empty.

| Measurement column | Definition |
| --- | --- |
| `experiment` | `control` for overflow 0.05, or `overflow` for the weakening study |
| `design`, `config`, `placement_seed` | Portable identifiers for a measurement |
| `util_pct` | Floorplan utilization as a percentage |
| `kind` | Baseline, combined seams, or a single-axis control |
| `width_sites`, `height_rows` | Seam dimensions |
| `pitch_sites`, `pitch_rows` | Paired X/Y pitches |
| `block_delta` | Additive block-utilization increment as a fraction |
| `placement_overflow` | Main global-placement stopping target |
| `grt_status` | Saved global-route completion state |
| `grt_wl_um` | Native OpenROAD global-route wirelength in micrometers |
| `drt_status` | `completed_clean`, `failed`, `incomplete`, or `not_run` |
| `drt_wl_um` | Native detailed-route wirelength in micrometers, when available |
| `drt_drc` | Saved detailed-route violation count |

Wirelength columns use native router measurements, including routed clock
networks. They do not use the separately extracted non-clock WL metric from
some earlier working tables. DRT summary comparisons use clean completed
samples. A failed sample can still have a reported WL value, but contributes
no clean DRT summary measurement. Empty values represent unavailable results.
Machine-specific filesystem paths have been replaced with portable identifiers.

`design_statistics.csv` counts the repaired netlist before CTS. Logical-net
counts include connected clock nets and exclude power/ground connectivity.
Cell area is the sum of instantiated LEF master areas, in square micrometers.

## Genus synthesis driver

`flow/genus/synthesize.tcl` runs `syn_generic`, `syn_map`, and `syn_opt` with
high effort. It sources `flow/genus/config.tcl`, which explicitly lists the
eight bundled TT RVT NLDM libraries. Edit the synthesis settings there.

| Setting | Meaning |
| --- | --- |
| `synth(top)` | RTL top module |
| `synth(threads)` | Synthesis CPU count |
| `synth(rtl_files)` | List of RTL source paths to supply |
| `synth(include_dirs)` | RTL include directories |
| `synth(defines)` | Preprocessor definitions |
| `synth(sdc)` | Input constraints path |
| `synth(out)` | Output directory |
| `synth(libraries)` | Explicit bundled TT Liberty paths |

After setting `synth(rtl_files)` and the corresponding top and constraints,
run `genus -files flow/genus/synthesize.tcl`. RTL sources are supplied by
the user. The released netlists are the repaired OpenROAD inputs described
above. Changes to synthesis settings apply to subsequent synthesis runs.

## Technology

The bundled `pdk/ASAP7` contains the two LEFs, sixteen SS/FF RVT NLDM Liberty files for OpenROAD,
and eight TT RVT NLDM Liberty files for Genus, plus their license files. They
come from `/home/jal216/pdk/ASAP7`, the installation used for the experiments.
LEF and Liberty files are gzip-compressed and read directly by OpenROAD.
Exact filenames are listed in `flow/openroad/config.tcl` and
`flow/genus/config.tcl`.

The bundle omits GDS, CCS libraries, unused threshold-voltage variants, the
6-track platform, datasheets, and Cadence-only technology views. OpenROAD and
Genus installations are supplied separately.

The small RC, track, and OpenRCX support files in `flow/openroad/support/`
originate from the ASAP7 platform support in
[OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/master/flow/platforms/asap7).
They provide OpenROAD-compatible estimation and extraction support. The RC
model is distinct from the Cadence QRC model used in the separate Innovus study.
