"""Check original cell/master preservation and CTS-only additions."""
import argparse
import json
from pathlib import Path
from guards import load_graph, check_graph

parser = argparse.ArgumentParser(__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--stage", choices=["grt", "detail"], default="grt")
args = parser.parse_args()
root = args.output
original = load_graph(root / "original_graph.tsv")
clocks = set((root / "clock_members.txt").read_text().splitlines())
actual = load_graph(root / ("grt_graph.tsv" if args.stage == "grt" else "routed_graph.tsv"))
result = check_graph(original, actual, False, clock_members=clocks)
if args.stage == "detail":
    placed = load_graph(root / "postcts_graph.tsv")
    result = check_graph(original, actual, False, clock_members=clocks, preserve=placed)
print(json.dumps(result, indent=2))
