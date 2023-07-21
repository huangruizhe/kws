#!/usr/bin/env python3

import sys
from nltk.stem import WordNetLemmatizer


def main():

    wordnet_lemmatizer = WordNetLemmatizer()
    for line in sys.stdin:
        if len(line) == 0:
            continue

        tokenization = line.lower().strip().split(" ")
        l_lemma = " ".join([wordnet_lemmatizer.lemmatize(w) for w in tokenization])
        print(l_lemma)


if __name__ == '__main__':
    main()

