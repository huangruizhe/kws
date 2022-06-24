#!/usr/bin/env python3

import sys
import os
import argparse
import logging
from tqdm import tqdm
import gzip
from collections import defaultdict, Counter


def get_doc_id_eval2000(uid):
    # en_4156-A_030185-030248
    return uid.split("-", 1)[0]


def get_doc_id_std2006(uid):
    # fsh_60262_exA_A_005670_007520
    first = uid.find('_', 0)
    second = first = uid.find('_', first + 1)
    return uid[:second]


def get_doc_id_callhome(uid):
    # en_4065_0A_00000
    return get_doc_id_std2006(uid)


def get_doc_id_swbd(uid):
    # sw02001-A_000098-001156
    return get_doc_id_eval2000(uid)


def find_ngrams(input_list, n):
    # https://stackoverflow.com/a/40923317/4563935
    # http://www.locallyoptimal.com/blog/2013/01/20/elegant-n-gram-generation-in-python/
    return zip(*[input_list[i:] for i in range(n)])


def get_df(lines, data_name, n):
    # `lines` should be a list of list of words, 
    #  with the first element in each list being the uid, 
    #  e.g.
    #  [
    #    ['abb', 'aaa', 'bbb'], 
    #    ['cca', 'abd'], 
    #  ...]

    logging.info("Getting DF for data_name: %s" % data_name)

    get_doc_id = None
    if data_name == "eval2000":
        get_doc_id = get_doc_id_eval2000
    elif data_name == "std2006":
        get_doc_id = get_doc_id_std2006
    elif data_name == "callhome":
        get_doc_id = get_doc_id_callhome
    elif data_name == "swbd":
        get_doc_id = get_doc_id_swbd
    else:
        logging.error("Dataset=%s is not implemented." % opts.dataset)
        exit(1)

    docs = defaultdict(list)
    logging.info("Collecting docs ...")
    # for line in tqdm(lines):
    for line in lines:
        uid = line[0]
        docid = get_doc_id(uid)

        if len(line) == 1:
            continue

        sent = line[1:]
        if len(sent) == 0:
            continue

        docs[docid].append(sent)
    
    logging.info("Counting df ...")
    df = Counter()
    for docid, sents in tqdm(docs.items()):
        # collect ngrams in this doc
        my_ngrams = set()
        for sent in sents:
            my_ngrams.update(find_ngrams(sent, n))

        df.update(my_ngrams)
    
    return df


def get_tf(lines, data_name, n):
    tf = Counter()
    # for line in tqdm(lines):
    for line in lines:
        uid = line[0]
        if len(line) == 1:
            continue

        sent = line[1:]
        if len(sent) == 0:
            continue

        tf.update(find_ngrams(sent, n))
    return tf