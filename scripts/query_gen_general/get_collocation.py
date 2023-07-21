#!/usr/bin/env python3

from fileinput import filename
import sys
import os
import argparse
import logging
from tqdm import tqdm
import gzip
from collections import defaultdict, Counter
import itertools
import nltk
from nltk.collocations import *
from nltk.stem import WordNetLemmatizer
from nltk.corpus import stopwords
from pathlib import Path
import re


# import local modules
# https://www.geeksforgeeks.org/python-import-from-parent-directory/
current = os.path.dirname(os.path.realpath(__file__))
parent = os.path.dirname(current)
sys.path.append(parent)
# print(sys.path)
import utils.utils as utils
from query_gen_general.get_dfidf import get_df, get_tf


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
    parser.add_argument('-f', '--freq_thres', type=int, default=3, help='')
    parser.add_argument('--lang', type=str, default="english", help='')

    opts = parser.parse_args()
    print(opts)
    return opts


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


def get_candidate_stems(opts, encoding):
    inputfiles = opts.input   # a list of files
    workdir = opts.workdir
    order = opts.order
    freq_thres = opts.freq_thres

    # word_pattern = re.compile("[\w\-\']+")
    # word_pattern = re.compile("^(?:(?:\w[\w\-\']*\w)|(\w))$")
    word_pattern = re.compile("^(?:(?:\w[\w\-]*\w)|(\w))$")  # English specific word patterns

    if order == 1:
        assert len(inputfiles) == 1
        logging.info(f"There are {len(inputfiles)} files. Loading ...")
        
        filename = inputfiles[0]
        lines = utils.read_multiple_files([filename], encoding=encoding, fn=lambda x: x)

        lines = [l.split() for l in lines]
        
        df = get_df(lines, order)
        tf = get_tf(lines, order)
        assert len(df) == len(tf)
        tfidf = dict()
        for w, w_df in df.items():
            
            # Filtering conditions (language dependent!)
            if not word_pattern.match(w[0]):
                continue
            if len(w[0]) <= 2:
                continue

            w_tf = tf[w]
            # You may customize your tf-idf score here:
            # tfidf[w] = w_tf * 1.0 / w_df
            tfidf[w] = w_tf * 1.0 / (w_df * w_df)
        rs = dict(sorted(tfidf.items(), key=lambda item: item[1], reverse=True)).items()
        logging.info(f"There are {len(rs)}/{len(df)} unigrams after filtering")

        outputfile = Path(workdir) / f"lemma_candidates.{order}.txt"
        utils.check_dir(outputfile.parent, create=True)
    else:
        logging.info(f"There are {len(inputfiles)} files. Loading ...")
        lines = utils.read_multiple_files(inputfiles, encoding=encoding)
        
        lines = [l.split() for l in lines]

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
        
        # stop words
        my_stopwords = set(stopwords.words(opts.lang))

        # very frequent words + very frequent short words
        freq = nltk.FreqDist(itertools.chain.from_iterable(lines))
        topk = 50
        my_freq_words = set(w for w, _ in freq.most_common(topk))
        my_freq_short_words = list()
        for w, _ in freq.most_common():
            if len(w) <= 3:
                my_freq_short_words.append(w)
                if len(my_freq_short_words) >= topk:
                    break
        my_freq_words.update(my_freq_short_words)
        my_stopwords.update(my_freq_words)

        n_before_filter = len(finder.ngram_fd)
        logging.info(f"There are {n_before_filter} {order}-grams before applying filters.")

        # The ngram has to appear in the tgt file for at least freq_thres times
        finder.apply_freq_filter(freq_thres)  # freq >= freq_thres will be kept
        logging.info(f"There are {len(finder.ngram_fd)} out of {n_before_filter} {order}-grams left after applying the frequency threshold ({freq_thres}) filter.")

        # The ngram will be removed if it meets the following conditions
        def filter_condition(*ng):
            # The ngrams meeting the following conditions will be removed.
            # These are just based on experience.
            #
            # - every word has length smaller than 2
            # - average word length < 2.5
            # - begin or end with stop words
            # - 50% of words in the ngram are stop words
            return all(map(lambda x: len(x) <= 2, ng)) or \
                sum(map(len, ng)) / len(ng) < 2.5 or \
                ng[0] in my_stopwords or \
                ng[-1] in my_stopwords or \
                sum([w in my_stopwords for w in ng]) / len(ng) >= 0.5 or \
                any([not word_pattern.match(w) for w in ng])

        finder.apply_ngram_filter(filter_condition)
        logging.info(f"There are {len(finder.ngram_fd)} out of {n_before_filter} {order}-grams left after applying the heuristics filter.")
        
        logging.info("Computing PMI ...")
        rs = finder.score_ngrams(measures.pmi)
    
        outputfile = Path(workdir) / f"lemma_candidates.{order}.thres{freq_thres}.txt"
        utils.check_dir(outputfile.parent, create=True)

    logging.info(f"Saving to output file: {outputfile}")
    with open(outputfile, "w", encoding=encoding) as fout:
        with tqdm(total=len(rs)) as pbar:
            for ngram, score in rs:
                ngram = " ".join(ngram)
                pbar.update(1)
                print(f"{ngram}\t{score}", file=fout)
    logging.info(f"Done: {outputfile}")


def main(opts):
    encoding = 'utf-8'
    get_candidate_stems(opts, encoding)


if __name__ == '__main__':
    opts = parse_opts()
    main(opts)
    # test()

