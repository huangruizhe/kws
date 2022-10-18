from collections import defaultdict
import logging
import argparse
import sys
import gzip


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--l1_lex', type=str, default=None, help='')
    parser.add_argument('--w2keys', type=str, default=None, help='')

    opts = parser.parse_args()
    return opts


def read_lex(filename):
    lex = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            word = fields[0]
            pronunciation = fields[1:]
            lex[word] = pronunciation
    # logging.info("len(lex)=%d" % len(lex))
    return lex


def process(uid, clat, words):
    ret = []
    for line in clat:
        w = line[2]
        if w not in words:
            continue
        key = f"{uid}_{line[0]}_{line[1]}"
        # print(f"{key} {w}")
        ret.append((key, w))
    return ret


def deduplicate(bin_words, opts):
    w2keys = defaultdict(list)
    for uid, ret in bin_words.items():
        for key, w in ret:
            w2keys[w].append(key)

    # with open(opts.w2keys, "w") as fout:
    with gzip.open(opts.w2keys, 'wt') as fout:
        for w, keys in w2keys.items():
            print(f"{w} {w}")
            print(f"{w} {' '.join(keys)}", file=fout)


def main(opts):
    l1_lex = read_lex(opts.l1_lex)
    words = l1_lex.keys()

    uid = None
    clat = list()
    bin_words = dict()
    for line in sys.stdin:
        line = line.strip()

        if len(line) == 0 and uid is not None:
            ret = process(uid, clat, words)
            bin_words[uid] = ret
            uid = None
            continue

        if uid is None:
            assert len(line.split()) == 1, f"Bad line: {line}"
            uid = line
            continue
        
        line = line.split()
        
        if len(line) == 2:  # last line of a clat
            continue
        
        assert len(line) == 4, f"Bad line: {line}"
    
        clat.append(line)

    assert uid is None
    deduplicate(bin_words, opts)


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
