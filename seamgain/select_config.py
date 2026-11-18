"""Select the RSC configuration of a design from one uniform reference run (Algorithm 1 of the paper).

The reference run is the uniform flow (width 0 and height 0 in flow/openroad/config.tcl), run with
OpenROAD's metrics output:

    openroad -exit -metrics uniform_metrics.json flow/openroad/flow.tcl

    python3 seamgain/select_config.py --metrics uniform_metrics.json \\
        --core-width-um 75.762 --core-height-um 75.6

Only the stages up to the legalization that follows CTS are used. The script reads from the metrics
file the HPWL before and after the two legalization steps and the utilization before each of them,
which give the inputs of SeamGain:

    e_dp   excess HPWL inflation of legalization
    e_cts  excess HPWL inflation of the legalization that follows CTS
    a_cts  clock-buffer area as a fraction of the core area
    U      utilization

The inputs can also be given directly (--e-dp, --e-cts, --a-cts, --utilization). The core width and
height (micrometers) determine the seam-area fraction of each candidate; with --core-area-um2 a
square core is assumed. By default the candidates are the 144 configurations swept in the paper;
--candidates reads another set from a CSV file with the columns width_sites, height_rows,
pitch_sites, pitch_rows and block_delta.

The script prints whether RSC should be applied and the selected configuration(s) as settings for
flow/openroad/config.tcl. --k N lists the N best-ranked configurations.
"""
import argparse
import itertools
import json
import os

import numpy as np
import pandas as pd

import seamgain as sg

WIDTHS_SITES = [10, 15]
HEIGHTS_ROWS = [2, 3]
PITCHES = [(240, 60), (260, 65), (280, 70), (300, 75), (320, 80), (360, 90)]     # (sites, rows)
DELTAS = [0.01, 0.02, 0.03, 0.04, 0.05, 0.06]


def reference_inputs(metrics_file, dbu_per_micron):
    """(e_dp, e_cts, a_cts, U) from the metrics file of a uniform run."""
    with open(metrics_file) as stream:
        pairs = json.loads(stream.read(), object_pairs_hook=list)      # the two legalization steps repeat the same keys
    def values(key):
        return [float(v) for k, v in pairs if k == key]
    hpwl = values('route__wirelength__estimated')       # HPWL after each legalization, micrometers
    delta = values('dpl__hpwl__delta')                  # HPWL increase of each legalization, database units
    util = values('utilization__before__dpl')           # percent
    if min(len(hpwl), len(delta), len(util)) < 2:
        raise SystemExit('%s does not contain two legalization steps (placement and CTS)' % metrics_file)
    before = [hpwl[i] - delta[i] / dbu_per_micron for i in (0, 1)]
    return hpwl[0] / before[0] - 1.0, hpwl[1] / before[1] - 1.0, (util[1] - util[0]) / 100.0, util[0] / 100.0


def candidates(args, e_dp, e_cts, a_cts, utilization):
    if args.candidates:
        c = pd.read_csv(args.candidates)
    else:
        c = pd.DataFrame([dict(width_sites=w, height_rows=h, pitch_sites=px, pitch_rows=py, block_delta=d)
                          for w, h, (px, py), d in itertools.product(WIDTHS_SITES, HEIGHTS_ROWS, PITCHES, DELTAS)])
    c['seam_fraction'] = [sg.seam_fraction(args.core_width_um, args.core_height_um, w, h, px, py)
                          for w, h, px, py in zip(c.width_sites, c.height_rows, c.pitch_sites, c.pitch_rows)]
    c['seam_utilization'] = sg.seam_utilization(utilization, c.seam_fraction, c.block_delta)
    c['seam_whitespace'] = sg.seam_whitespace(c.seam_fraction, c.seam_utilization)
    c['packing_density'] = sg.packing_density(utilization, c.seam_whitespace)
    c['headroom'] = c.seam_whitespace / a_cts
    c['e_dp'], c['e_cts'], c['a_cts'], c['utilization'] = e_dp, e_cts, a_cts, utilization
    return c


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--metrics', help='metrics file of the uniform reference run (openroad -metrics)')
    ap.add_argument('--dbu-per-micron', type=float, default=1000.0)
    ap.add_argument('--e-dp', type=float)
    ap.add_argument('--e-cts', type=float)
    ap.add_argument('--a-cts', type=float)
    ap.add_argument('--utilization', type=float)
    ap.add_argument('--core-width-um', type=float)
    ap.add_argument('--core-height-um', type=float)
    ap.add_argument('--core-area-um2', type=float)
    ap.add_argument('--candidates', help='CSV file with candidate configurations')
    ap.add_argument('--k', type=int, default=1, help='number of configurations to list')
    ap.add_argument('--parameters', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'parameters.json'))
    args = ap.parse_args()

    if args.metrics:
        e_dp, e_cts, a_cts, utilization = reference_inputs(args.metrics, args.dbu_per_micron)
    elif None not in (args.e_dp, args.e_cts, args.a_cts, args.utilization):
        e_dp, e_cts, a_cts, utilization = args.e_dp, args.e_cts, args.a_cts, args.utilization
    else:
        ap.error('give --metrics, or all of --e-dp, --e-cts, --a-cts and --utilization')
    if args.core_area_um2 and not (args.core_width_um and args.core_height_um):
        args.core_width_um = args.core_height_um = float(np.sqrt(args.core_area_um2))
    if not (args.core_width_um and args.core_height_um):
        ap.error('give --core-width-um and --core-height-um, or --core-area-um2')

    with open(args.parameters) as stream:
        model = json.load(stream)
    params = [model['parameters'][name] for name in sg.PARAMETER_NAMES]

    print('reference run: e_dp = %.4f, e_cts = %.4f, a_cts = %.4f, U = %.4f' % (e_dp, e_cts, a_cts, utilization))
    ranked = sg.rank(candidates(args, e_dp, e_cts, a_cts, utilization), params, model['delta_max'], model['epsilon'])
    if not len(ranked):
        print('no packing-feasible candidate (seam density target >= %.0f%%, packing density <= %.4f): keep the uniform flow'
              % (100 * sg.MIN_SEAM_UTILIZATION, model['delta_max']))
        return
    best = ranked.predicted.max()
    print('%d packing-feasible candidates; best predicted reduction of routed wirelength: %.1f%% (threshold tau = %.1f%%)'
          % (len(ranked), best, model['tau']))
    if best < model['tau']:
        print('decision: keep the uniform flow')
        return
    print('decision: apply RSC')
    for i, (_, row) in enumerate(ranked.iloc[:args.k].iterrows(), 1):
        print('  %d. width %d  height %d  pitch_x %d  pitch_y %d  delta %.2f    predicted %.1f%%, seam density target %.1f%%, '
              'seam whitespace %.2f%%, packing density %.4f'
              % (i, row.width_sites, row.height_rows, row.pitch_sites, row.pitch_rows, row.block_delta, row.predicted,
                 100 * row.seam_utilization, 100 * row.seam_whitespace, row.packing_density))


if __name__ == '__main__':
    main()
