import logging
import argparse
import os, sys
from tqdm import tqdm
import random

# import local modules
# https://www.geeksforgeeks.org/python-import-from-parent-directory/
current = os.path.dirname(os.path.realpath(__file__))
parent = os.path.dirname(current)
sys.path.append(parent)
# print(sys.path)
from query_gen.get_dfidf import find_ngrams


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='Find the words in wordlist that do not occur in text',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--text', type=str, default=None, help='')
    parser.add_argument('--wordlist', type=str, default=None, help='')
    parser.add_argument('--maxorder', type=int, default=3, help='')
    parser.add_argument('--seed', type=int, default=17, help='')

    opts = parser.parse_args()
    logging.info(f"Parameters: {vars(opts)}")
    return opts


def main(opts):
    all_ngrams = set()
    
    logging.info(f"Loading ngrams from {opts.text} ...")
    with open(opts.text, "r") as fin:
        for line in tqdm(fin.readlines()):
            line = line.strip()
            if len(line) == 0:
                continue

            line = line.split()
            uid = line[0]
            if len(line) == 1:
                continue

            text = line[1:]

            for order in range(1, opts.maxorder + 1):
                ngrams = find_ngrams(text, order)
                all_ngrams.update([tuple(ngram) for ngram in ngrams])

    logging.info(f"Checking the occurrence ...")    
    zero_occurrence_words = set()
    with open(opts.wordlist, "r") as fin:    
        # assumeing the format to be "kwid word1 word2 .." for each line
        for line in tqdm(fin.readlines()):
            line = line.strip()
            if len(line) == 0:
                continue

            line = line.split()
            kwid = line[0]
            if len(line) == 1:
                continue

            word = tuple(line[1:])
            if word not in all_ngrams:
                zero_occurrence_words.add(word)

    # for each order, print a sample of 20 words
    sample_size_per_order = 20
    random.seed(opts.seed)
    for order in range(1, opts.maxorder + 1):
        all_words = [words for words in zero_occurrence_words if len(words) == order]
        
        if len(all_words) > sample_size_per_order:
            sample = random.sample(all_words, sample_size_per_order)
        else:
            sample = all_words
        
        for words in sample:
            print(" ".join(words) + " 0")


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
