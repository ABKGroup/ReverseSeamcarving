"""Original-cell, connectivity/polarity and physical invariants.\nAdapted from the validated matched IO/buffer experiment.\n"""
import csv
import re
from fractions import Fraction
from pathlib import Path

class Graph:
    def __init__(self):
        self.cells = {}
        self.pins = {}
        self.ports = {}
        self.port_kinds = {}


def load_graph(path: Path) -> Graph:
    graph = Graph()
    with path.open() as stream:
        for row in csv.reader(stream, delimiter="\t"):
            if row[0] == "C":
                _, name, master, buf, inv = row
                if name in graph.cells:
                    raise ValueError(f"duplicate instance {name}")
                graph.cells[name] = (master, bool(int(buf)), bool(int(inv)))
            elif row[0] == "I":
                _, inst, pin, net, inp, outp = row
                graph.pins[(inst, pin)] = (net, bool(int(inp)), bool(int(outp)))
            elif row[0] == "P":
                graph.ports[row[1]] = row[2]
                if len(row) == 5:
                    graph.port_kinds[row[1]] = (bool(int(row[3])), bool(int(row[4])))
            else:
                raise ValueError(f"unknown graph row: {row[:2]}")
    if not graph.cells:
        raise ValueError(f"empty graph {path}")
    return graph


class ParityUnion:
    def __init__(self):
        self.parent = {}
        self.parity = {}
        self.rank = {}

    def find(self, node):
        if node not in self.parent:
            self.parent[node] = node
            self.parity[node] = 0
            self.rank[node] = 0
        parent = self.parent[node]
        if parent == node:
            return node, 0
        root, phase = self.find(parent)
        self.parity[node] ^= phase
        self.parent[node] = root
        return root, self.parity[node]

    def union(self, a, b, invert):
        ra, pa = self.find(a)
        rb, pb = self.find(b)
        if ra == rb:
            if pa ^ pb != invert:
                raise ValueError("inconsistent inversion cycle in inserted repeaters")
            return
        if self.rank[ra] > self.rank[rb]:
            self.parent[rb] = ra
            self.parity[rb] = pa ^ pb ^ invert
        else:
            self.parent[ra] = rb
            self.parity[ra] = pa ^ pb ^ invert
            if self.rank[ra] == self.rank[rb]:
                self.rank[rb] += 1


def signature(graph: Graph, original_cells: set[str]):
    """Original pin connectivity, collapsing added buffers with inversion parity."""
    extra = set(graph.cells) - original_cells
    repeater_pins = {name: [] for name in extra}
    for (name, pin), value in graph.pins.items():
        if name in extra:
            repeater_pins[name].append(value)
    union = ParityUnion()
    drivers = {}
    for (inst, pin), (net, inp, outp) in graph.pins.items():
        if net and outp:
            drivers.setdefault(net, set()).add(("I", inst, pin))
    for name, (inp, outp) in graph.port_kinds.items():
        if inp and graph.ports[name]:
            drivers.setdefault(graph.ports[name], set()).add(("P", name))
    upstream = {}
    for name in sorted(extra):
        master, buf, inv = graph.cells[name]
        if not (buf or inv):
            raise ValueError(f"inserted non-buffer/inverter {name}: {master}")
        inputs = {net for net, inp, outp in repeater_pins[name] if inp}
        outputs = {net for net, inp, outp in repeater_pins[name] if outp}
        if len(inputs) != 1 or len(outputs) != 1 or "" in inputs | outputs:
            raise ValueError(f"inserted repeater has invalid connectivity: {name}")
        input_net, output_net = next(iter(inputs)), next(iter(outputs))
        if len(drivers.get(output_net, ())) != 1:
            raise ValueError(f"inserted repeater output has multiple drivers: {name}")
        if output_net in upstream:
            raise ValueError(f"inserted repeaters share an output net: {name}")
        upstream[output_net] = input_net
        union.union(input_net, output_net, int(inv))
    resolved = set()
    for node in upstream:
        path = set()
        while node in upstream and node not in resolved:
            if node in path:
                raise ValueError("cycle in inserted repeater network")
            path.add(node)
            node = upstream[node]
        resolved.update(path)
    endpoints = [(("I", name, pin), value[0])
                 for (name, pin), value in graph.pins.items() if name in original_cells]
    endpoints.extend((("P", name), net) for name, net in graph.ports.items())
    groups = {}
    for endpoint, net in endpoints:
        root, phase = union.find(net if net else ("FLOAT", endpoint))
        groups.setdefault(root, []).append((endpoint, phase))
    result = []
    for group in groups.values():
        group.sort()
        anchor = group[0][1]
        result.append(tuple((endpoint, phase ^ anchor) for endpoint, phase in group))
    return tuple(sorted(result))


def check_graph(original: Graph, actual: Graph, allow_signal: bool,
                clock_members=frozenset(), preserve: Graph | None = None) -> dict:
    for name, info in original.cells.items():
        if actual.cells.get(name) != info:
            raise ValueError(f"original instance deleted, renamed or resized: {name}")
    if preserve:
        for name, info in preserve.cells.items():
            if actual.cells.get(name) != info:
                raise ValueError(f"placement-added buffer removed/resized later: {name}")
    if set(original.ports) != set(actual.ports):
        raise ValueError("top-level ports changed")
    if original.port_kinds and original.port_kinds != actual.port_kinds:
        raise ValueError("top-level port directions changed")
    actual_old_pins = {pin for pin in actual.pins if pin[0] in original.cells}
    if actual_old_pins != set(original.pins):
        raise ValueError("original pin identities changed")
    extra = set(actual.cells) - set(original.cells)
    clocks = extra & set(clock_members)
    signals = extra - clocks
    if signals and not allow_signal:
        raise ValueError(f"signal insertion forbidden, but found {len(signals)} extra cells")
    for name in signals:
        if not (actual.cells[name][1] or actual.cells[name][2]):
            raise ValueError(f"inserted signal logic instead of repeater: {name}")
    for name in clocks:
        if not (actual.cells[name][1] or actual.cells[name][2]):
            raise ValueError(f"CTS added non-buffer logic/cloned gate: {name}")
    originals = set(original.cells)
    if signature(original, originals) != signature(actual, originals):
        raise ValueError("logical connectivity or polarity changed beyond buffer insertion")
    return {
        "input_instances": len(original.cells),
        "input_buffers": sum(info[1] for info in original.cells.values()),
        "input_inverters": sum(info[2] for info in original.cells.values()),
        "signal_buffers_added": sum(actual.cells[name][1] for name in signals),
        "signal_inverters_added": sum(actual.cells[name][2] for name in signals),
        "signal_repeaters_added": len(signals),
        "clock_buffers_added": sum(actual.cells[name][1] for name in clocks),
        "clock_inverters_added": sum(actual.cells[name][2] for name in clocks),
        "final_instances": len(actual.cells),
    }


def pin_geometry(path: Path) -> dict:
    """Compare assigned pin geometry, allowing CTS to update USE CLOCK/net names."""
    text = path.read_text()
    units = int(re.search(r"UNITS DISTANCE MICRONS\s+(\d+)", text)[1])
    section = re.search(r"^PINS\s+\d+\s*;(.*?)^END PINS", text, re.M | re.S)
    if not section:
        raise ValueError(f"missing PINS section: {path}")
    result = {}
    for record in re.findall(r"^-\s+.*?;\s*$", section[1], re.M | re.S):
        name = re.sub(r"\\(.)", r"\1", re.match(r"-\s+(\S+)", record)[1])
        place = re.findall(r"\+\s+(?:FIXED|PLACED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)", record)
        if len(place) != 1:
            raise ValueError(f"expected one assigned position for {name}")
        x, y, orientation = place[0]
        shapes = []
        for layer, x0, y0, x1, y1 in re.findall(
                r"\+\s+LAYER\s+(\S+)(?:\s+MASK\s+\d+)?\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)",
                record):
            shapes.append((layer, *(Fraction(int(v), units) for v in (x0, y0, x1, y1))))
        if not shapes:
            raise ValueError(f"no pin shapes for {name}")
        result[name] = (Fraction(int(x), units), Fraction(int(y), units),
                        orientation, tuple(sorted(shapes)))
    return result


def component_map(path: Path) -> dict:
    """Physical cell invariants, ignoring PLACED versus FIXED status."""
    result = {}
    units = None
    inside = False
    record = []
    with path.open() as stream:
        for line in stream:
            match = re.match(r"UNITS DISTANCE MICRONS\s+(\d+)", line)
            if match:
                units = int(match[1])
            if line.startswith("COMPONENTS "):
                inside = True
                continue
            if line.startswith("END COMPONENTS"):
                break
            if not inside:
                continue
            record.append(line)
            if ";" not in line:
                continue
            text = "".join(record).lstrip()
            record = []
            match = re.match(r"-\s+(\S+)\s+(\S+).*?\+\s+(?:PLACED|FIXED)\s*"
                             r"\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)", text, re.S)
            if not match or units is None:
                raise ValueError(f"unplaced or unparseable component in {path}: {text[:150]}")
            name, master, x, y, orientation = match.groups()
            name = re.sub(r"\\(.)", r"\1", name)
            result[name] = (master, Fraction(int(x), units), Fraction(int(y), units), orientation)
    if not result:
        raise ValueError(f"no components in {path}")
    return result

