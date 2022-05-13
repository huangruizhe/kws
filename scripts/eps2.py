import sys

def main():
    for line in sys.stdin:
        line = line.strip()
        
        if len(line) == 0:
            print()
        else:
            fields = line.split()
            if len(fields) <= 2:
                print(line)
            elif fields[2] == "<eps>" or fields[2] == "<eps2>":
                scores = fields[3].split(",")
                scores_new = f"{scores[0]},{0.693},{scores[2]}"   # set the prob of eps arc to be 0.5  (neg log prob = 0.693)
                print(f"{fields[0]} {fields[1]} <eps2> {scores_new}")
            else:
                print(line)

if __name__ == '__main__':
    main()
