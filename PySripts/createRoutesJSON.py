import json
from osm_handler import OSMHandler

def main():
    osm_map = OSMHandler()
    osm_map.apply_file("../includes/brasilia.osm")
    osm_map.set_bounding_box("../includes/brasilia.osm")

    routes = []

    for r in osm_map.relations:
        route = {"name" : "", "parts" : []}
        if ["route", "bus"] in r["tags"]:
            for t in r["tags"]:
                if t[0] == "name":
                    route["name"] = t[1]
            for m in r["members"]:
                if m["type"] == "w":
                    route["parts"].append(str(m["ref"]))
            routes.append(route)

    file = {}
    for r in routes:
        if r["name"] in file.keys():
            file[r["name"]].extend(r["parts"])
        else:
            file[r["name"]] = r["parts"].copy()

    with open("../includes/routes.json", "w") as f:
        f.write(json.dumps(file).replace('],', '],\n'))


if __name__ == "__main__":
    main()