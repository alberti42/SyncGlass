#!/usr/bin/env python3
"""Split Design/AppIcon.svg into the layers that Icon Composer imports.

AppIcon.svg is the Illustrator drawing. Its artwork sits in one group, clipped
to a rounded rectangle for preview, with these children in order:

    0     background rectangle
    1     handle (group)
    2-4   rim, bevel and glass base (circles)
    5     cloud and liquid (group)
    6-8   glass shading, highlight, hairline

Each layer keeps the full 1024 x 1024 canvas, without the preview clip, so the
layers stay aligned in Icon Composer. usvg turns Illustrator's CSS classes into
plain attributes. Run from the repository root: Design/split-layers.py
"""
import copy, os, subprocess, tempfile
import xml.etree.ElementTree as ET

SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
HERE = os.path.dirname(os.path.abspath(__file__))
LAYERS = {
    "1-background.svg": [0],
    "2-handle.svg": [1],
    "3-rim.svg": [2, 3, 4],
    "4-cloud.svg": [5],
    "5-glass.svg": [6, 7, 8],
}

root = ET.parse(os.path.join(HERE, "AppIcon.svg")).getroot()
defs = root.find(f"{{{SVG}}}defs")
artwork = list(root.find(f"{{{SVG}}}g").find(f"{{{SVG}}}g"))
assert len(artwork) == 9, f"expected 9 elements in the artwork group, found {len(artwork)}"

out = os.path.join(HERE, "layers")
os.makedirs(out, exist_ok=True)
for name, indices in LAYERS.items():
    layer = ET.Element(f"{{{SVG}}}svg", {"viewBox": "0 0 1024 1024", "width": "1024", "height": "1024"})
    layer.append(copy.deepcopy(defs))
    for i in indices:
        layer.append(copy.deepcopy(artwork[i]))
    with tempfile.NamedTemporaryFile("wb", suffix=".svg", delete=False) as tmp:
        ET.ElementTree(layer).write(tmp, xml_declaration=True, encoding="utf-8")
    subprocess.run(["usvg", tmp.name, os.path.join(out, name)], check=True)
    os.unlink(tmp.name)
    print(os.path.join("Design/layers", name))
