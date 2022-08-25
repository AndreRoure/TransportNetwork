import json

def main():
    with open("../includes/routesProcessed.json") as f:
        file = json.load(f)

    newJson = dict()
    for route in file.keys():
        newJson[route] = list(dict.fromkeys(file[route]))

    with open("../includes/routesClean.json", "w") as f:
        f.write(json.dumps(newJson).replace('],', '],\n'))

if __name__ == "__main__":
    main()