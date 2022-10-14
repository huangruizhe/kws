from collections import defaultdict
import enum
import logging
import argparse
import sys
from unionfind import unionfind


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--nbest', type=int, default=-1, help='how many best results (for each KWID) should be printed (int, default -1, i.e. no limit')
    parser.add_argument('--duptime', type=int, default=50, help='duplicates detection, tolerance (in frames) for being the same hits (int,  default = 50)')
    parser.add_argument('--likes', default=False, action='store_true', help='The smaller the score, the better')
    parser.add_argument('--probs', default=True, action='store_true', help='The bigger the score, the better')

    opts = parser.parse_args()
    return opts


def process_kw_results(results, duptime, nbest):
    # do the de-duplication of the hitlist

    uid2hits = defaultdict(list)
    for i, h in enumerate(results):
        uid2hits[h[1]].append(i)

    u = unionfind(len(results)) # There are this many items.

    for uid, hits in uid2hits.items():
        for k, i1 in enumerate(hits):
            for i2 in hits[k+1: ]:
                if abs(results[i1][5] - results[i2][5]) < duptime:
                    u.unite(i1, i2) # Set them to the same group.

    new_results = list()
    for group in u.groups():
        max_i = None
        max_score = -99999999
        max_span = 0
        assert len(group) > 0, f"group={group} is problematic."
        for i in group:
            score = results[i][4]
            if score == max_score:
                span = results[i][3] - results[i][2]
                if span > max_span:
                    max_i = i
                    max_score = score
                    max_span = span
            elif score > max_score:
                span = results[i][3] - results[i][2]
                max_i = i
                max_score = score
                max_span = span
            else:
                pass
        new_results.append(results[max_i])

    new_results = sorted(new_results, key=lambda x: x[4], reverse=True)
    assert len(new_results) <= len(results), f"len(new_results) <= len(results) assertion is failed: {len(new_results)} > {len(results)}"

    if nbest > 0:
        new_results = new_results[:nbest]
    return new_results


def main(opts):

    cur_kwid = None
    kwid2results = defaultdict(list)
    for line in sys.stdin:
        line = line.strip().split()
        assert len(line) == 5, f"Bad number of columns in raw results {line}"
        
        kwid = line[0]
        uid = line[1]
        start = int(line[2])
        end = int(line[3])
        score = -float(line[4]) if opts.likes else float(line[4])
        midpoint = start + end / 2.0
        
        kwid2results[kwid].append((kwid, uid, start, end, score, midpoint))

    for kwid, results in sorted(kwid2results.items(), key=lambda item: item[0]):
        new_results = process_kw_results(results, opts.duptime, opts.nbest)
        for h in new_results:
            print(f"{h[0]} {h[1]} {h[2]} {h[3]} {-h[4] if opts.likes else h[4]}")


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
