"""Regenerate the touch layout catalogue from MAME's official -listxml archive."""
import json
import pathlib
import sys
import xml.etree.ElementTree as ET
import zipfile

CATALOGUE = pathlib.Path(__file__).resolve().parents[1] / "LightRetro/Resources/Catalogue"


def count_buttons(machine):
    controls = [control for control in machine.findall("input/control")
                if control.get("player", "1") == "1"]
    if not controls:
        return None
    count = max(int(control.get("buttons", "0")) for control in controls)
    return min(6, max(2, count))


def main(archive):
    titles = json.loads((CATALOGUE / "mame-titles.json").read_text())
    # Six is the default and also covers sets missing from the export.
    groups = {n: [] for n in range(2, 6)}
    with zipfile.ZipFile(archive) as release, release.open("mame0289.xml") as source:
        for _, machine in ET.iterparse(source, events=("end",)):
            if machine.tag != "machine":
                continue
            stem = machine.get("name")
            if stem in titles:
                count = count_buttons(machine)
                if count in groups:
                    groups[count].append(stem)
            machine.clear()
    (CATALOGUE / "arcade-buttons.json").write_text(json.dumps(groups, indent=1) + "\n")
    print({n: len(names) for n, names in groups.items()})


if __name__ == "__main__":
    main(sys.argv[1])
