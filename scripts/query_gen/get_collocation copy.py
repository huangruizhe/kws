#!/usr/bin/env python3

import sys
import os
import argparse
import logging
import tqdm
import gzip
from collections import defaultdict, Counter
import nltk
from nltk.collocations import *


# https://www.geeksforgeeks.org/python-import-from-parent-directory/
current = os.path.dirname(os.path.realpath(__file__))
parent = os.path.dirname(current)
sys.path.append(parent)
# print(parent)
from utils.utils import *


logging.basicConfig(
    format = "%(asctime)s — %(levelname)s — %(funcName)s:%(lineno)d — %(message)s", 
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='Get collocations',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('-i', '--input', type=str, action='append', required=True, help='path to the text files')
    parser.add_argument('-w', '--workdir', type=str, help='')
    parser.add_argument('-n', '--order', type=int, help='')
    parser.add_argument('-f', '--freq', type=int, default=3, help='')

    opts = parser.parse_args()
    return opts



def generate_pmi_score(inputfiles, outputfile, order, encoding, opts):
    logging.info("Generate PMI scores for: " + str(inputfiles))

    logging.info("Loading files ...")
    lines = read_multiple_files(inputfiles, encoding=encoding)

    # https://www.nltk.org/book/ch03.html
    if order == 2:
        logging.info("Get BigramCollocationFinder ...")
        finder = BigramCollocationFinder.from_documents(lines)
        measures = nltk.collocations.BigramAssocMeasures()
    elif order == 3:
        logging.info("Get TrigramCollocationFinder ...")
        finder = TrigramCollocationFinder.from_documents(lines)
        measures = nltk.collocations.TrigramAssocMeasures()
    elif order == 4:
        logging.info("Get QuadgramCollocationFinder ...")
        finder = QuadgramCollocationFinder.from_documents(lines)
        measures = nltk.collocations.QuadgramAssocMeasures()
    else:
        logging.info("This order is not supported: %d" % order)
        exit(1)
    
    def filter_condition(*ng):
        return all(map(lambda x: len(x) <= 2, ng)) or \
            sum(map(len, ng)) / len(ng) < 2.5
    finder.apply_ngram_filter(filter_condition)

    logging.info("Get PMI ...")
    # rs = finder.score_ngrams(measures.raw_freq)
    rs = finder.score_ngrams(measures.pmi)
    logging.info("There are %d %d-grams." % (len(rs), order))
    
    logging.info("Saving to output file: " + outputfile)
    with open(outputfile, "w", encoding=encoding) as fout:
        with tqdm.tqdm(total=len(rs)) as pbar:
            for ngram, score in rs:
                ngram = " ".join(ngram)
                pbar.update(1)
                print(f"{ngram}\t{score}", file=fout)
    logging.info("Done.")


def find_ngrams(input_list, n):
    # https://stackoverflow.com/a/40923317/4563935
    # http://www.locallyoptimal.com/blog/2013/01/20/elegant-n-gram-generation-in-python/
    return zip(*[input_list[i:] for i in range(n)])


def get_topk_unigrams(lines, topk, fn=lambda x: True):
    unigram_counter = Counter()
    for line in lines:   # line = [w1, w2, ...]
        unigram_counter.update(line)
    
    rs = []
    for w, c in unigram_counter.most_common():
        if fn(w):
            rs.append((w, c))
            if len(rs) == topk:
                break
    return set([w for w, _ in rs])


def get_queries_for(tgtfile, inputfiles, outputfile, order, encoding, opts):
    logging.info("Generate PMI scores for testfile: " + tgtfile)

    logging.info("Loading files ...")
    lines = read_multiple_files(inputfiles, encoding=encoding)

    # all_test_ngrams = set()
    tgtlines = read_multiple_files([tgtfile], encoding=encoding)
    # for sentence in testlines:
    #     all_test_ngrams.update(find_ngrams(sentence, order))

    # https://www.nltk.org/book/ch03.html
    if order == 2:
        logging.info("Get BigramCollocationFinder ...")
        finder = BigramCollocationFinder.from_documents(lines)
        finder_tgt = BigramCollocationFinder.from_documents(tgtlines)
        measures = nltk.collocations.BigramAssocMeasures()
    elif order == 3:
        logging.info("Get TrigramCollocationFinder ...")
        finder = TrigramCollocationFinder.from_documents(lines)
        finder_tgt = TrigramCollocationFinder.from_documents(tgtlines)
        measures = nltk.collocations.TrigramAssocMeasures()
    elif order == 4:
        logging.info("Get QuadgramCollocationFinder ...")
        finder = QuadgramCollocationFinder.from_documents(lines)
        finder_tgt = QuadgramCollocationFinder.from_documents(tgtlines)
        measures = nltk.collocations.QuadgramAssocMeasures()
    else:
        logging.info("This order is not supported: %d" % order)
        exit(1)
    
    # The ngram has to appear in the tgt file for at least freq_thres times
    freq_thres = opts.freq
    finder_tgt.apply_freq_filter(freq_thres)  # freq >= freq_thres will be kept
    ngrams_set_tgt = set(finder_tgt.ngram_fd)
    # logging.info(f"len(ngrams_set_tgt)={len(ngrams_set_tgt)}, len(finder.ngram_fd)={len(finder.ngram_fd)}")
    # not_in_tgt = lambda *ng: ng not in ngrams_set_tgt  # https://www.geeksforgeeks.org/packing-and-unpacking-arguments-in-python/

    short_freq_unigrams = get_topk_unigrams(tgtlines, 70, lambda x: len(x)<=3)
    freq_unigrams = get_topk_unigrams(tgtlines, 100)
    logging.info("short_freq_unigrams (70):")
    print(short_freq_unigrams)
    logging.info("freq_unigrams (100):")
    print(freq_unigrams)

    def filter_condition(*ng):
        # The ngrams meeting the following conditions will be removed.
        # These are just based on experience.
        #
        # 1) not in ngrams_set_tgt
        # 2) every word has length smaller than 2
        # 3) average word length < 2.5
        # 4) begin or end with short and frequent words
        # 5) 50% of words in the ngram are frequent words
        return (ng not in ngrams_set_tgt) or \
            all(map(lambda x: len(x) <= 2, ng)) or \
            sum(map(len, ng)) / len(ng) < 2.5 or \
            ng[0] in short_freq_unigrams or \
            ng[-1] in short_freq_unigrams or \
            sum([w in freq_unigrams for w in ng]) / len(ng) >= 0.5
        
        # return (ng not in ngrams_set_tgt) or \
        #     all(map(lambda x: x <= 2, len_ws)) or \
        #     sum(len_ws) / len_ng < 2.5 or \
        #     ng[0] in short_freq_unigrams or \
        #     ng[-1] in short_freq_unigrams # or \
        #     # sum([w in freq_unigrams for w in ng]) / len_ng >= 0.5

    finder.apply_ngram_filter(filter_condition)

    logging.info("Get PMI ...")
    # rs = finder.score_ngrams(measures.raw_freq)
    rs = finder.score_ngrams(measures.pmi)
    logging.info("There are %d %d-grams." % (len(rs), order))
    
    logging.info("Saving to output file: " + outputfile)
    with open(outputfile, "w", encoding=encoding) as fout:
        with tqdm.tqdm(total=len(rs)) as pbar:
            for ngram, score in rs:
                ngram = " ".join(ngram)
                pbar.update(1)
                print(f"{ngram}\t{score}", file=fout)
    logging.info("Done.")


def test():
    # https://www.nltk.org/howto/collocations.html
    # https://www.nltk.org/_modules/nltk/collocations.html#BigramCollocationFinder

    # collocation finders by default consider all ngrams in a text as candidate collocations
    bigram_measures = nltk.collocations.BigramAssocMeasures()
    trigram_measures = nltk.collocations.TrigramAssocMeasures()
    fourgram_measures = nltk.collocations.QuadgramAssocMeasures()

    # finder = BigramCollocationFinder.from_words(nltk.corpus.genesis.words('english-web.txt'))
    finder = BigramCollocationFinder.from_words(['a', 'b', 'a', 'b', 'c'])
    # rs = finder.nbest(bigram_measures.pmi, 10)
    # rs = finder.score_ngrams(bigram_measures.raw_freq)
    rs = finder.score_ngrams(bigram_measures.pmi)
    print(len(rs))
    print(rs)
    print(len(finder.ngram_fd))
    print(finder.ngram_fd)
    print(set(finder.ngram_fd))


def main(opts):
    encoding = 'utf-8'

    if opts.target is None:
        generate_pmi_score(opts.input, opts.output, opts.order, encoding, opts)
    else:
        get_queries_for(opts.target, opts.input, opts.output, opts.order, encoding, opts)

if __name__ == '__main__':
    opts = parse_opts()
    main(opts)
    # test()

