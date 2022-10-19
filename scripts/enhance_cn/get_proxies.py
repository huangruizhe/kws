from collections import defaultdict
import logging
import argparse
import sys
import gzip
from jellyfish import jaro_distance
import heapq
from weighted_levenshtein import lev
import math
from scipy.special import logsumexp
import numpy as np


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
    parser.add_argument('--confusion', type=str, default=None, help='')

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
            
            # pronunciation = fields[2:]
            
            lexiconp[word].append([prob, pronunciation])

    for w, w_pronunciations in lexiconp.items():
        psum = sum([s for s, pr in w_pronunciations])
        for s_pr in w_pronunciations:
            s_pr[0] /= psum

    logging.info(f"len(lexiconp) = {len(lexiconp)}")
    return lexiconp


def read_confusion(filename, phones):
    # initialized to be -1
    insert_costs = np.full(128, -1, dtype=np.float64)
    delete_costs = np.full(128, -1, dtype=np.float64)
    substitute_costs = np.full((128, 128), -1, dtype=np.float64)

    max_cost = 0
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            assert len(fields) == 3

            if fields[0] not in phones or fields[1] not in phones:
                continue

            cost = float(fields[2])
            ph1 = ord("A") + phones[fields[0]]
            ph2 = ord("A") + phones[fields[1]]

            # https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5b/local/generate_proxy_keywords.sh#L27
            if fields[0] == "<eps>":  # insertion
                insert_costs[ph2] = cost
            elif fields[1] == "<eps>":  # deletion
                delete_costs[ph1] = cost
            else: # For substitution
                substitute_costs[ph1, ph2] = cost

            if cost > max_cost:
                max_cost = cost
    
    insert_costs[insert_costs < 0] = max_cost + 1
    delete_costs[delete_costs < 0] = max_cost + 1
    substitute_costs[substitute_costs < 0] = max_cost + 1

    confusion = (insert_costs, delete_costs, substitute_costs)
    return confusion


def get_edit_distances0(w1, lexiconp):
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


def get_edit_distances(w1, lexiconp, confusion):
    w1_pronunciations = lexiconp.get(w1, None)
    if w1_pronunciations is None:
        return None
    
    dist = {x: -math.inf for x in lexiconp.keys()}
    for p1, pro1 in w1_pronunciations:
        for w2, w2_pronunciations in lexiconp.items():
            if w2 == w1:
                continue
            else:
                for p2, pro2 in w2_pronunciations:
                    cost = lev(pro2, pro1, insert_costs=confusion[0], delete_costs=confusion[1], substitute_costs=confusion[2])
                    
                    dist[w2] = logsumexp([dist[w2], math.log(p1) + math.log(p2) - cost]) 
    return dist


def find_topk(big_array, k):
    return heapq.nlargest(k, big_array, key = lambda x: x[1])


def find_proxies(words, lexiconp, confusion, k):
    # assume that words are in lexiconp

    for i, w in enumerate(words):
        dist = get_edit_distances(w, lexiconp, confusion)

        # Finding the top K items in a list efficiently
        # http://stevehanov.ca/blog/?id=122
        my_proxies = find_topk(dist.items(), k)
        for proxy in my_proxies:
            print(f"{w} {proxy[1]} {proxy[0]}")
        
        if i % 100 == 0:
            logging.info(f"progress: {i}/{len(words)}")


def main(opts):
    phones = read_phones(opts.phones_txt)
    l1_lexiconp = read_lexiconp(opts.l1_lexiconp, phones)
    confusion = read_confusion(opts.confusion, phones)

    l2_words = list()
    with open(opts.l2_words, "r") as fin:
        for line in fin:
            line = line.strip()
            if len(line) == 0:
                continue
            l2_words.append(line)
    logging.info(f"len(l2_words) = {len(l2_words)}")

    find_proxies(l2_words, l1_lexiconp, confusion, opts.topk)


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
