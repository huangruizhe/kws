from collections import defaultdict
import logging
import argparse
import sys
import gzip
from jellyfish import jaro_distance
import heapq


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--l1_lexiconp', type=str, default=None, help='')
    parser.add_argument('--l2_words', type=str, default=None, help='')
    parser.add_argument('--phones_txt', type=str, default=None, help='')
    parser.add_argument('--topk', type=int, default=10, help='')

    opts = parser.parse_args()
    return opts


def read_phones(filename):
    phones = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            phone = fields[0]
            id = int(fields[1])
            phones[phone] = id
    logging.info(f"len(phones) = {len(phones)}")
    return phones


def read_lexiconp(filename, phones):
    lexiconp = defaultdict(list)
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            word = fields[0]
            prob = float(fields[1])
            # use ascii to re-encode the phones -- this is to be used to compute edit distance later
            pronunciation = "".join([chr(ord("A") + phones[ph]) for ph in fields[2:]])
            lexiconp[word].append([prob, pronunciation])

    for w, w_pronunciations in lexiconp.items():
        psum = sum([s for s, pr in w_pronunciations])
        for s_pr in w_pronunciations:
            s_pr[0] /= psum

    logging.info(f"len(lexiconp) = {len(lexiconp)}")
    return lexiconp


def get_edit_distances(w1, lexiconp):
    w1_pronunciations = lexiconp.get(w1, None)
    if w1_pronunciations is None:
        return None
    
    dist = {x:0 for x in lexiconp.keys()}
    for p1, pro1 in w1_pronunciations:
        for w2, w2_pronunciations in lexiconp.items():
            if w2 == w1:
                dist[w2] = 0
            else:
                for p2, pro2 in w2_pronunciations:
                    score = jaro_distance(pro1, pro2)
                    dist[w2] += p1 * p2 * score
    return dist


def find_topk(big_array, k):
    return heapq.nlargest(k, big_array, key = lambda x: x[1])


def find_proxies(words, lexiconp, k):
    # assume that words are in lexiconp

    for w in words:
        dist = get_edit_distances(w, lexiconp)

        # Finding the top K items in a list efficiently
        # http://stevehanov.ca/blog/?id=122
        my_proxies = find_topk(dist.items(), k)
        for proxy in my_proxies:
            print(f"{w} {proxy[1]} {proxy[0]}")


def main(opts):
    phones = read_phones(opts.phones_txt)
    l1_lexiconp = read_lexiconp(opts.l1_lexiconp, phones)

    l2_words = list()
    with open(opts.l2_words, "r") as fin:
        for line in fin:
            line = line.strip()
            if len(line) == 0:
                continue
            l2_words.append(line)
    logging.info(f"len(l2_words) = {len(l2_words)}")

    find_proxies(l2_words, l1_lexiconp, opts.topk)


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
