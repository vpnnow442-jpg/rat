#!/usr/bin/env python3
"""Bundle src/ into a Roblox place file you can open straight in Studio.

    python3 build.py            -> ChaosCourse.rbxlx + sourcemap.json

File naming follows the Rojo convention, so the same src/ also works with Rojo:
    Foo.server.luau -> Script      Foo.client.luau -> LocalScript
    Foo.luau        -> ModuleScript    folders     -> Folder
"""

import json
import os
import uuid
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "ChaosCourse.rbxlx")

# (place path, src dir) - where each src folder lands in the game tree
MOUNTS = [
    (["ReplicatedFirst"], "ReplicatedFirst"),
    (["ReplicatedStorage"], "ReplicatedStorage"),
    (["ServerScriptService"], "ServerScriptService"),
    (["StarterPlayer", "StarterPlayerScripts"], "StarterPlayer/StarterPlayerScripts"),
]

SERVICE_PROPS = {
    "Workspace": '<bool name="StreamingEnabled">false</bool>',
    "Players": '<bool name="CharacterAutoLoads">false</bool>',
}

SERVICES = ["Workspace", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService",
            "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Players",
            "SoundService"]


def ref():
    return "RBX" + uuid.uuid4().hex.upper()


def classify(filename):
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if filename.endswith(suffix):
            return filename[: -len(suffix)], cls
    return None, None


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def walk(path):
    """Return a list of nodes: {name, cls, source?, file?, children}."""
    nodes = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            nodes.append({"name": entry, "cls": "Folder", "children": walk(full), "file": None})
        else:
            name, cls = classify(entry)
            if cls:
                with open(full, encoding="utf-8") as f:
                    src = f.read()
                nodes.append({"name": name, "cls": cls, "source": src, "children": [],
                              "file": os.path.relpath(full, ROOT)})
    return nodes


def xml_node(node, depth):
    pad = "  " * depth
    props = [f'<string name="Name">{escape(node["name"])}</string>']
    if "source" in node:
        props.append(f'<ProtectedString name="Source">{cdata(node["source"])}</ProtectedString>')
    out = [f'{pad}<Item class="{node["cls"]}" referent="{ref()}">',
           f'{pad}  <Properties>{"".join(props)}</Properties>']
    for child in node["children"]:
        out.append(xml_node(child, depth + 1))
    out.append(f"{pad}</Item>")
    return "\n".join(out)


def build_tree():
    services = {name: {"name": name, "cls": name, "children": []} for name in SERVICES}
    for place_path, src_dir in MOUNTS:
        children = walk(os.path.join(SRC, src_dir))
        parent = services[place_path[0]]
        for name in place_path[1:]:
            match = next((c for c in parent["children"] if c["name"] == name), None)
            if not match:
                match = {"name": name, "cls": name, "children": []}
                parent["children"].append(match)
            parent = match
        parent["children"].extend(children)
    return services


def write_rbxlx(services):
    parts = ['<roblox version="4">']
    for name in SERVICES:
        svc = services[name]
        extra = SERVICE_PROPS.get(name, "")
        parts.append(f'  <Item class="{name}" referent="{ref()}">')
        parts.append(f'    <Properties><string name="Name">{name}</string>{extra}</Properties>')
        for child in svc["children"]:
            parts.append(xml_node(child, 2))
        parts.append("  </Item>")
    parts.append("</roblox>")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(parts) + "\n")


def sourcemap_node(node):
    out = {"name": node["name"], "className": node["cls"]}
    if node.get("file"):
        out["filePaths"] = [node["file"]]
    if node["children"]:
        out["children"] = [sourcemap_node(c) for c in node["children"]]
    return out


def write_sourcemap(services):
    tree = {"name": "Game", "className": "DataModel",
            "children": [sourcemap_node(services[n]) for n in SERVICES]}
    with open(os.path.join(ROOT, "sourcemap.json"), "w", encoding="utf-8") as f:
        json.dump(tree, f, indent=1)


def count(nodes):
    return sum((1 if "source" in n else 0) + count(n["children"]) for n in nodes)


if __name__ == "__main__":
    tree = build_tree()
    write_rbxlx(tree)
    write_sourcemap(tree)
    scripts = sum(count(s["children"]) for s in tree.values())
    print(f"Built {os.path.basename(OUT)} with {scripts} scripts")
