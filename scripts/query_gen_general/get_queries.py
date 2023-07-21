#!/usr/bin/env python3

import sys
import os
import argparse
import logging
from tqdm import tqdm
import gzip
from collections import Counter, defaultdict
from pathlib import Path

# import local modules
# https://www.geeksforgeeks.org/python-import-from-parent-directory/
current = os.path.dirname(os.path.realpath(__file__))
parent = os.path.dirname(current)
sys.path.append(parent)
# print(parent)
import utils.utils as utils
from query_gen_general.get_dfidf import find_ngrams


logging.basicConfig(
    format = "%(asctime)s — %(levelname)s — %(funcName)s:%(lineno)d — %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='Text processing for phrases extraction. The processing is done line by line.',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('-i', '--input', type=str, action='append', required=True, help='path to the text files')
    parser.add_argument('-r', '--raw', type=str, action='append', required=True, help='path to the text files')
    parser.add_argument('-d', '--dict', type=str, help='')
    parser.add_argument('-w', '--workdir', type=str, help='')
    parser.add_argument('-n', '--order', type=int, help='')
    parser.add_argument('-s', '--suffix', type=str, default=None, help='')

    opts = parser.parse_args()
    return opts


def load_dict(filename):
    word2score = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            word = " ".join(fields[:-1])
            score = float(fields[-1])
            word2score[word] = score
    logging.info("len(word2score)=%d" % len(word2score))
    return word2score

                
def get_queries(opts, encoding):
    inputfiles = opts.input   # a list of files
    workdir = opts.workdir
    order = opts.order
    rawfiles = opts.raw
    
    logging.info(f"There are {len(inputfiles)} files. Loading ...")
    lines_lemma = utils.read_multiple_files(inputfiles, encoding=encoding)
    lines = utils.read_multiple_files(rawfiles, encoding=encoding)

    word2score = load_dict(opts.dict)

    keywords = Counter()
    for line, line_lemma in zip(lines, lines_lemma):
        line = line.strip()
        if len(line) == 0:
            continue
        
        line_lemma = line_lemma.lower().split()
        line = line.lower().split()

        assert len(line) == len(line_lemma)

        for ngram, ngram_lemma in zip(find_ngrams(line, order), find_ngrams(line_lemma, order)):
            ngram = " ".join(ngram)
            ngram_lemma = " ".join(ngram_lemma)
            if ngram_lemma in word2score:
                keywords.update([ngram])

    logging.info(f"There are {len(keywords)} keywords.")

    suffix = f".{opts.suffix}" if opts.suffix is not None else ""
    outputfile = Path(workdir) / f"keywords.{order}{suffix}.txt"
    logging.info(f"Saving to output file: {outputfile}")
    with open(outputfile, "w", encoding=encoding) as fout:
        rs = dict(sorted(keywords.items(), key=lambda item: item[1], reverse=True)).items()
        for w, c in rs:
            print(f"{w}\t{c}", file=fout)

    logging.info(f"Done: {outputfile}")


def main(opts):
    encoding = 'utf-8'    
    get_queries(opts, encoding)


if __name__ == '__main__':
    opts = parse_opts()
    main(opts)
