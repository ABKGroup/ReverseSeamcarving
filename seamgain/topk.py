"""SeamGain with k RSC runs instead of one.

    python3 seamgain/topk.py [--k 1 2 3]

Algorithm 1 of the paper returns one configuration per case. Here it returns the k configurations
that it ranks first (see seamgain.rank), all k are run, and the one with the smallest measured
wirelength is kept. The script reports the reduction of global-routing wirelength that this
procedure obtains on the 11 cases of tpu, ethmac and jpeg, and its share of the best of the 144
swept configurations. As in evaluate.py, the parameters and the packing limit of a design are
obtained from the other two designs.

The measurements use one placement seed per configuration, so keeping the best of k runs also
selects for a favorable seed; the last lines of the output quantify this effect.
"""
import argparse

import numpy as np
import pandas as pd

import seamgain as sg


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--k', type=int, nargs='+', default=[1, 2, 3])
    args = ap.parse_args()

    runs, _ = sg.load_dataset()
    seed1 = runs[runs.placement_seed == 1]
    fitset = sg.fitting_runs(runs)
    rows = []
    for design in sg.TRAINING_DESIGNS:
        train = sg.training_designs(design)
        params = sg.fit(fitset[fitset.design.isin(train)])
        delta_max = sg.packing_limit(seed1[seed1.design.isin(train)])
        for case, cand in seed1[seed1.design == design].groupby('case'):
            ranked = sg.rank(cand, params, delta_max)
            row = dict(case=case, design=design, util_pct=int(cand.util_pct.iloc[0]), near_ties=int(ranked.near_tie.sum()),
                       best_of_sweep=cand[cand.ok].reduction.max())
            for k in args.k:
                chosen = ranked.iloc[:k]
                done = chosen[chosen.ok]
                row['k=%d' % k] = done.reduction.max() if len(done) else 0.0       # 0: no run completed, the uniform flow is kept
            rows.append(row)
    t = pd.DataFrame(rows).set_index('case')
    columns = ['k=%d' % k for k in args.k]
    pd.options.display.float_format = '{:.2f}'.format
    print('Reduction of global-routing wirelength (percent) of the best of the k selected configurations')
    print(t[['near_ties'] + columns + ['best_of_sweep']].to_string())
    mean = t[columns + ['best_of_sweep']].mean()
    print('\naverage over %d cases:' % len(t))
    for k, c in zip(args.k, columns):
        print('  k = %d: %.2f%%, i.e., %.0f%% of the best-of-sweep reduction (%.2f%%)' % (k, mean[c], 100 * mean[c] / mean.best_of_sweep, mean.best_of_sweep))

    # how much the maximum of k single-seed measurements gains from seed variation alone
    spread = runs[runs.ok & runs.reduction.notnull()].groupby(['case', 'config']).reduction.agg(['std', 'count'])
    spread = spread[spread['count'] >= 4]
    sd = float(np.sqrt((spread['std'] ** 2).mean()))
    rng = np.random.RandomState(0)
    print('\nseed-to-seed standard deviation of the reduction of one configuration: %.2f percentage points (%d configurations with at least four seeds)'
          % (sd, len(spread)))
    for k in args.k:
        if k > 1:
            print('  the best of %d equally good configurations reads %.2f percentage points higher from seed variation alone'
                  % (k, rng.normal(0.0, sd, (200000, k)).max(axis=1).mean()))


if __name__ == '__main__':
    main()
