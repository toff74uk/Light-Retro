"""Generate arcade CHD lookup data from the official MAME 0.289 -listxml archive."""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile

OUTPUT = Path(__file__).resolve().parents[1] / "LightRetro/Resources/Catalogue/arcade-discs.json"


def generate(archive):
    sets, parents = {}, {}
    with ZipFile(archive) as release, release.open("mame0289.xml") as source:
        for _, machine in ET.iterparse(source, events=("end",)):
            if machine.tag != "machine":
                continue
            name = machine.get("name")
            parents[name] = machine.get("romof")
            discs = {disk.get("name"): disk.get("sha1") for disk in machine.findall("disk")
                     if disk.get("sha1")}
            if discs and machine.get("isdevice") != "yes" and machine.get("isbios") != "yes":
                sets[name] = {"discs": discs}
            machine.clear()

    for name, record in sets.items():
        ancestors = []
        parent = parents[name]
        while parent and parent not in ancestors:
            ancestors.append(parent)
            parent = parents.get(parent)
        if ancestors:
            record["parents"] = ancestors
        # MAME accepts a parent's filename for an identical disc.
        for parent in ancestors:
            for disc, digest in sets.get(parent, {}).get("discs", {}).items():
                if digest in record["discs"].values():
                    record["discs"].setdefault(disc, digest)
    return sets


if __name__ == "__main__":
    sets = generate(sys.argv[1])
    lines = [f"  {json.dumps(name)}: {json.dumps(sets[name], sort_keys=True)}" for name in sorted(sets)]
    OUTPUT.write_text("{\n" + ",\n".join(lines) + "\n}\n")
