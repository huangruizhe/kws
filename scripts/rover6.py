#!/usr/bin/env python3

import argparse
from collections import defaultdict
from email.policy import default
import enum
import logging
import edit_distance
from matplotlib.pyplot import bone
import numpy as np
from regex import P
from scipy.special import logsumexp
from scipy.stats import gmean
from statistics import mean
from pathlib import Path
import sys
import os
import gzip
import pickle

from tqdm import tqdm
from jellyfish import jaro_distance

from check_cm_distribution import wer_output_filter

# References:
# https://github.com/belambert/edit-distance
# https://github.com/roy-ht/editdistance


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

EPSILON = "<eps>"
EPSILON2 = "<eps2>"
UNK = "<unk>"

def parse_opts():
    parser = argparse.ArgumentParser(
        description='This script converts nbest lists to kaldi\'s compact lattices',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--workdir', type=str, help='')
    parser.add_argument('--nbest', type=str, help='txt file contains lines of (uid, log-prob, hyp) pairs')
    parser.add_argument('--dur', type=str, default=None, help='utt2dur')
    parser.add_argument('--words', type=str, default=None, help='words')
    parser.add_argument('--ali', type=str, default=None, help='ali')
    parser.add_argument('--ali_shift', type=int, default=0, help='ali_shift')
    parser.add_argument('--refali', type=str, default=None, help='refali')
    parser.add_argument('--scale', type=float, default=1.0, help='scaling factor')
    parser.add_argument('--quiet', type=bool, default=True, help='')
    parser.add_argument('--oov', type=str, default="<unk>", help='')
    parser.add_argument('--eps', type=str, default="<eps>", help='')
    parser.add_argument('--text', type=str, default=None, help='')
    parser.add_argument('--score_type', type=str, default="", help='')
    parser.add_argument('--no_print_sausage', action='store_true')
    parser.add_argument('--print_w_pos', action='store_true')
    parser.add_argument('--ctm', type=str, default=None, help='')
    parser.add_argument('--nsize', type=int, default=None, help='')
    parser.add_argument('--data_points', type=str, default=None, help='')
    parser.add_argument('--htk_lattice_dir', type=str, default=None, help='')
    parser.add_argument('--npz_lattice_dir', type=str, default=None, help='')
    parser.add_argument('--confidence', type=str, default=None, help='')
    parser.add_argument('--intrinsic_conf', action='store_true', default=False)
    parser.add_argument('--intrinsic_time', action='store_true', default=False)
    parser.add_argument('--keywords', type=str, default=None, help='')

    opts = parser.parse_args()

    logging.info(f"Parameters: {vars(opts)}")
    return opts


def read_dur(filename):
    utt2dur = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            uid = fields[0]
            dur = float(fields[1])  # in seconds
            utt2dur[uid] = dur
    logging.info("len(utt2dur)=%d" % len(utt2dur))
    return utt2dur


def read_text(filename):
    utt2text = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            uid = fields[0]
            text = fields[1:]
            utt2text[uid] = text
    logging.info("len(utt2text)=%d" % len(utt2text))
    return utt2text


def read_words(filename):
    id2word = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            word = fields[0]
            wid = int(fields[1])
            id2word[wid] = word
    logging.info("len(id2word)=%d" % len(id2word))
    return id2word


def read_ali(filename, id2word, ali_shift=0, frame_rate=0.01, text_mode=False):
    # TODO: Kaldi alignment of espnet's output may have <unk>, but in espnet's output it is not <unk>
    
    factor = frame_rate / 0.01

    utt2ali = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split(maxsplit = 1)
            uid = fields[0]
            if len(fields) == 1:
                ali = []
            else:
                ali = map(lambda x: x.strip().split(), fields[1].split(";")) 
                # ali = map(lambda x: (id2word[int(x[0])], round(int(x[1]) / 3.0)), ali)
                if text_mode:
                    ali = [(x[0], round(int(x[1]) / factor)) for x in ali]
                else:
                    ali = [(id2word[int(x[0])], round(int(x[1]) / factor) + ali_shift) for x in ali]
            utt2ali[uid]= ali
    logging.info("len(utt2ali)=%d" % len(utt2ali))
    return utt2ali


def read_word_scores(filename):
    uid2word_scores = dict()
    try:
        with open(filename, mode="r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip().split()
                # if len(line) == 0:
                #     word_scores.append((None, None))
                #     continue
                uid = line[0]
                scores = line[1:] if len(line) > 1 else []
                if uid not in uid2word_scores:
                    uid2word_scores[uid] = list()
                uid2word_scores[uid].append([float(s) for s in scores])
        return uid2word_scores
    except:
        logging.info(f"File does not exist: {filename}")
        logging.info(f"Using None.")
        return None


def read_tags(filename):
    uid2tags = dict()
    try:
        with open(filename, mode="r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip().split()
                # if len(line) == 0:
                #     tags.append((None, None))
                #     continue
                uid = line[0]
                tags = line[1:] if len(line) > 1 else []
                if uid not in uid2tags:
                    uid2tags[uid] = list()
                uid2tags[uid].append(tags)
        return uid2tags
    except:
        logging.info(f"File does not exist: {filename}")
        logging.info(f"Using None.")
        return None


def load_keywords(opts):
    keywords_file = opts.keywords
    
    logging.info(f"Loading keywords from: {keywords_file}")

    keywords = set()
    with open(keywords_file, "r") as fin:
        for line in fin:
            line = line.strip()
            if len(line) == 0:
                continue
            
            line = line.split(maxsplit=1)
            wid = line[0]
            w = line[1]

            # if len(w.split()) != 1:  # we only consider single-word query
            #     continue 
            # keywords.add(w)

            for w in w.split():   # we add any word in the query list
                keywords.add(w)

    print(f"There are {len(keywords)} keywords.")
    return keywords


def log_mean(li):
    return logsumexp(li) - np.log(len(li))


class Hypothesis:
    def __init__(self, words, score=None, words_scores=None, timing=None, tags=None, rank=None):
        self.words = words
        self.utterance_score = score
        self.words_scores = words_scores
        self.timing = timing
        self.tags = tags
        self.rank = rank
    
    def __len__(self):
        return len(self.words)
    
    def __str__(self):
        return f"[{self.rank}] {' '.join(self.words)} {self.utterance_score}"


class Utterance:
    def __init__(self, uid, ref_words=None, dur=None, hyps=None, ali=None):
        self.uid = uid
        self.ref_words = ref_words
        self.dur = dur
        self.ali = ali
        self.refali = None
        self.hyps = hyps   # A list of Hypothesis
        self.sausage = None

    @classmethod
    def read_nbest_list(cls, opts):
        workdir = Path(opts.workdir)

        ####################################
        # Load nbest list
        ####################################
        uid2utt = dict()
        nbest_path = workdir / "nbest.txt"
        with open(nbest_path, mode="r", encoding="utf-8") as f:
            logging.info(f"Loading: {nbest_path}")
            uid = None
            hyps = list()
            for line in f:
                # assuming the input (nbest file) to be of this format for each line:
                # (uid, log-prob, sentence)
                # In Kaldi, the "log-prob" can be positive, but it does not matter if we normalize the posterior for each sentence

                line = line.rstrip().split()
                if len(line) == 0:
                    continue

                if line[0] == uid:
                    # There can be empty hypothesis in the nbest list. We will save them now, but will ignore them later
                    words = line[2:] if len(line) >= 3 else []
                    hyps.append(Hypothesis(words, score=float(line[1]), rank=len(hyps)+1))                        
                else:
                    if uid:
                        uid2utt[uid] = Utterance(uid, hyps=hyps)
                    
                    uid = line[0]
                    hyps = list()
                    words = line[2:] if len(line) >= 3 else []
                    hyps.append(Hypothesis(words, score=float(line[1]), rank=len(hyps)+1))
                        
            if uid:
                uid2utt[uid] = Utterance(uid, hyps=hyps)
            
            logging.info(f"Done {len(uid2utt)} utterances.")

        ####################################
        # Load word level scores
        ####################################
        # this file must have the same number of rows as "workdir/nbest"
        w_score_path = workdir / f"nbest_w_scores{opts.score_type}.txt"
        if opts.score_type != "_pos" and w_score_path.exists():
        # if w_score_path.exists():
            logging.info(f"Loading: {w_score_path}")
            uid2word_scores = read_word_scores(w_score_path)
            for uid, utt in uid2utt.items():
                my_word_scores = uid2word_scores[uid]
                assert len(utt.hyps) == len(my_word_scores), f"{uid} {len(utt.hyps)} != {len(my_word_scores)}"
                for hyp, word_scores in zip(utt.hyps, my_word_scores):
                    if len(hyp.words) > 0 and hyp.words[-1] != "⁇":
                        assert len(hyp.words) == len(word_scores), f"{uid}-{hyp.rank} {len(hyp.words)} != {len(word_scores)}, {hyp.words}, {word_scores}"
                    else:
                        assert len(hyp.words) >= len(word_scores), f"{uid}-{hyp.rank} {len(hyp.words)} != {len(word_scores)}, {hyp.words}, {word_scores}"
                    hyp.words_scores = word_scores

        ####################################
        # Load tags
        ####################################
        # this file must have the same number of rows as "workdir/nbest"
        tag_path = workdir / "nbest_tags.txt"
        if tag_path.exists():
            logging.info(f"Loading: {tag_path}")
            uid2tags = read_tags(tag_path)
            for uid, utt in uid2utt.items():
                mytags = uid2tags[uid]
                assert len(utt.hyps) == len(mytags), f"{len(utt.hyps)} != {len(mytags)}"
                for hyp, tags in zip(utt.hyps, mytags):
                    if len(hyp.words) > 0 and hyp.words[-1] != "⁇":
                        assert len(hyp.words) == len(tags), f"{uid}-{hyp.rank} {len(hyp.words)} != {len(tags)}, {hyp.words}, {tags}"
                    else:
                        assert len(hyp.words) >= len(tags), f"{uid}-{hyp.rank} {len(hyp.words)} != {len(tags)}, {hyp.words}, {tags}"
                    hyp.tags = tags

        ####################################
        # Load 1best alignment (timing information)
        ####################################
        if opts.ali is not None and Path(opts.ali).exists():
            logging.info(f"Loading: {opts.ali}")
            id2word = read_words(opts.words)
            uid2ali = read_ali(opts.ali, id2word, ali_shift=opts.ali_shift, frame_rate=0.01)
            for uid, utt in uid2utt.items():
                utt.ali = uid2ali.get(uid, [])   # Note that there can be empty or failed alignment

        ####################################
        # Load reference alignment 
        ####################################
        if opts.refali is not None and Path(opts.refali).exists():
            logging.info(f"Loading: {opts.refali}")
            id2word = read_words(opts.words)
            uid2refali = read_ali(opts.refali, id2word, frame_rate=0.01, text_mode=True)
            for uid, utt in uid2utt.items():
                utt.refali = uid2refali.get(uid, [])

        ####################################
        # Load duration
        ####################################
        if opts.dur is not None:
            logging.info(f"Loading: {opts.dur}")
            uid2dur = read_dur(opts.dur)
            for uid, utt in uid2utt.items():
                utt.dur = uid2dur[uid]

        ####################################
        # Load reference text
        ####################################
        if opts.text is not None:
            logging.info(f"Loading: {opts.text}")
            uid2text = read_text(opts.text)
            for uid, utt in uid2utt.items():
                utt.ref_words = uid2text[uid]
        
        # score normalization
        for uid, utt in uid2utt.items():
            utt.utterance_score_normalization(opts.scale, opts.nsize)

        # some clean-up
        for uid, utt in uid2utt.items():
            utt.clean_up_hyps()
        
        # some clean-up
        for uid, utt in uid2utt.items():
            utt.validate(opts.nsize)

        return uid2utt
    
    def utterance_score_normalization(self, scale, nsize):
        # https://github.com/espnet/espnet/issues/1378
        utt_scores = list()
        for h in self.hyps[0: nsize]:
            utt_scores.append(h.utterance_score)
        
        # http://www.kasimte.com/2020/02/14/how-does-temperature-affect-softmax-in-machine-learning.html
        utt_scores = np.asarray(utt_scores) * scale
        logsum = logsumexp(utt_scores)
        utt_scores -= logsum
        
        for h, s in zip(self.hyps, utt_scores):
            h.utterance_score = s

    def clean_up_hyps(self):
        # remove the empty hypothesis, and re-number the ranks
        # remove the non-sense words if necessary
        new_hyps = list()
        for h in self.hyps:
            # empty hypothesis
            # if len(h.words) == 0:
            #     continue
            
            # non-sense words
            while len(h.words) > 0 and h.words[-1] == "⁇":
                if h.words_scores is not None and len(h.words) == len(h.words_scores):
                    h.words_scores = h.words_scores[:-1]
                if h.tags is not None and len(h.words) == len(h.tags):
                    h.tags = h.tags[:-1]
                h.words = h.words[:-1]

            # if len(h.words) == 0:
            #     continue
            
            h.rank = len(new_hyps) + 1
            new_hyps.append(h)
        
        self.hyps = new_hyps

    def validate(self, nsize):
        for hyp in self.hyps:
            if hyp.words_scores is not None:
                assert len(hyp.words) == len(hyp.words_scores), f"{self.uid}-{hyp.rank} {len(hyp.words)} != {len(hyp.words_scores)}, {hyp.words}, {hyp.words_scores}"
            if hyp.tags is not None:
                assert len(hyp.words) == len(hyp.tags), f"{self.uid}-{hyp.rank} {len(hyp.words)} != {len(hyp.tags)}, {hyp.words}, {hyp.tags}"
        
        utt_scores = [h.utterance_score for h in self.hyps[0: nsize]]
        logsum = logsumexp(utt_scores)
        assert abs(logsum - 0) < 1e-6


    def build_sausage_from_nbest(self, score_type="_pos", nsize=None):
        # logging.info(f"Building sausage for uid={self.uid}")

        if len(self.hyps) == 0:
            logging.info(f"uid={self.uid} has an empty nbest list (1)")
            self.sausage = None
            return
        
        nsize = nsize if nsize is not None else len(self.hyps)

        ali_check_ok = self.ali is not None \
            and len(self.ali) > 0 \
            and len(self.hyps) > 0 and len([w_t for w_t in self.ali if w_t[0] != EPSILON]) == len(self.hyps[0].words)

        if self.ali is not None and len(self.ali) > 0:
        # if ali_check_ok:
            # logging.info(self.ali)
            self.sausage = Sausage(ali=self.ali, place_holder=True)
            offset = 0
        else:
            logging.warning(f"{self.uid} ali is not valid. Now using 1-best hyp as ali: {self.ali} ---- {self.hyps[0].words}")
            offset = 0
            while offset < len(self.hyps):
                if len(self.hyps[offset]) > 0:
                    self.sausage = Sausage(hyp=self.hyps[offset], place_holder=True)
                    offset += 1
                    # nsize -= 1
                    break
                else:
                    offset += 1
            if self.sausage is None:
                logging.info(f"uid={self.uid} has an empty nbest list (2)")
                return
        
        # for hyp in self.hyps[offset:nsize]:
        for hyp in self.hyps[0:nsize]:
            # logging.info(str(hyp))
            # if len(hyp) > 0:
            self.sausage.add_hyp(hyp, score_type)
        
        # don't forget to finalize the weight
        self.sausage.finalize_weight(score_type=score_type)

        # get timing
        self.sausage.get_timing(self.dur, frame_rate=0.01)

        nbins, nlinks = self.sausage.stats()
        logging.info(f"sausage for uid={self.uid}: {nbins} bins, {nlinks} links")

        # Sanity check:
        # if score_type == "_pos":
        #     for i_bin, bin in enumerate(self.sausage.sausage_bins):
        #         mysum = np.exp(logsumexp([h.utterance_score for h in self.hyps if len(h) > 0]))
        #         if abs(np.exp(bin.get_weight(func=logsumexp)) - mysum) >= 1e-4:
        #             logging.info(bin)
        #         assert abs(np.exp(bin.get_weight(func=logsumexp)) - mysum) < 1e-5, f"{i_bin}-th bin weight={np.exp(bin.get_weight(func=logsumexp))}"
        return self.sausage
    
    def align_sausage_with_reference0(self):
        # TODO: This alignment is not perfect, as there can be ambiguity in the alignment. 
        #  We should align the sausage in a way that:
        # 1. maximize the scores
        # 2. respect the timing
        sm = edit_distance.SequenceMatcher(a=self.ref_words, b=self.sausage.sausage_bins, test=SausageBin.test, action_function=edit_distance.highest_match_action)
        edits = sm.get_opcodes()

        for elem in edits:
            # logging.info(elem)
            if elem[0] == "equal":
                w = self.ref_words[elem[1]]
                bin = self.sausage.sausage_bins[elem[3]]
                for w_, link in bin.word2link.items():
                    if w == w_:
                        link.tag = 1
                    else:
                        link.tag = 0
            elif elem[0] == "replace":
                bin = self.sausage.sausage_bins[elem[3]]
                for w_, link in bin.word2link.items():
                    link.tag = 0
            elif elem[0] == "insert":
                bin = self.sausage.sausage_bins[elem[3]]
                for w_, link in bin.word2link.items():
                    link.tag = 0
            elif elem[0] == "delete":
                pass
            else:
                logging.error(f"Cannot reach here! elem[0]={elem[0]}")
                exit(1)
        
        # TODO: Also check the timing of the alignment, as this can make a difference in KWS

        # deduplicate mechanism similar to local/kws/filter_kws_results.pl
        duptime = 50
        for i, bin_i in enumerate(self.sausage.sausage_bins):
            dur_diff = bin_i.dur
            j = i + 1
            while j < len(self.sausage.sausage_bins):
                if dur_diff >= duptime:
                    break
                bin_j = self.sausage.sausage_bins[j]
                for w, link in bin_i.word2link.items():
                    if w in bin_j:  # dup detected!
                        if link.weight >= bin_j.word2link[w].weight:
                            link.tag = max(link.tag, bin_j.word2link[w].tag)
                            bin_j.word2link[w].tag = -1
                        else:
                            bin_j.word2link[w].tag = max(link.tag, bin_j.word2link[w].tag)
                            link.tag = -1
                dur_diff += bin_j.dur


    def deduplicated_weight_dependent(self, duptime):
        for i, bin_i in enumerate(self.sausage.sausage_bins):
            dur_diff = bin_i.dur / 2
            j = i + 1
            while j < len(self.sausage):
                bin_j = self.sausage.sausage_bins[j]

                dur_diff += bin_j.dur / 2
                if dur_diff >= duptime:
                    break
                
                for w, link in bin_i.word2link.items():
                    if w == EPSILON:
                        continue

                    if link.tag == 0 or link.tag == -1:
                        continue
                    
                    # if w in bin_j:  # dup detected!
                    #     if link.weight >= bin_j.word2link[w].weight:
                    #         link.tag = max(link.tag, bin_j.word2link[w].tag)
                    #         bin_j.word2link[w].tag = -1
                    #     else:
                    #         bin_j.word2link[w].tag = max(link.tag, bin_j.word2link[w].tag)
                    #         link.tag = -1

                    # Now link.tag == 1
                    if w in bin_j and bin_j.word2link[w].tag == 1:  # dup detected!
                        if link.weight >= bin_j.word2link[w].weight:
                            bin_j.word2link[w].tag = 0
                        else:
                            link.tag = 0
                
                dur_diff += bin_j.dur / 2
                j += 1

    def deduplicated_weight_independent(self, duptime):
        for i, bin_i in enumerate(self.sausage.sausage_bins):
            dur_diff = bin_i.dur / 2
            j = i + 1
            while j < len(self.sausage):
                bin_j = self.sausage.sausage_bins[j]

                dur_diff += bin_j.dur / 2
                if dur_diff >= duptime:
                    break
                
                for w, link in bin_i.word2link.items():
                    if w == EPSILON:
                        continue

                    if link.tag == 0 or link.tag == -1:
                        continue
                    
                    # if w in bin_j:  # dup detected!
                    #     if link.weight >= bin_j.word2link[w].weight:
                    #         link.tag = max(link.tag, bin_j.word2link[w].tag)
                    #         bin_j.word2link[w].tag = -1
                    #     else:
                    #         bin_j.word2link[w].tag = max(link.tag, bin_j.word2link[w].tag)
                    #         link.tag = -1                    

                    # Now link.tag == 1
                    if w in bin_j and bin_j.word2link[w].tag == 1:  # dup detected!
                        link_i = link
                        link_j = bin_j[w]
                        # If there are more than 85% of hypothesis passing through each of them,
                        # we should keep both of them.
                        thres = max(len(self.hyps) * 0.85, 10)
                        if len(link_i.uids) >= thres and len(link_j.uids) >= thres:
                            pass
                        else:
                            # Now, which one to keep?
                            #
                            # Heuristics here: we keep the only one link with largest number of uids,
                            # but its score will be updated to the largest score,
                            # and the other links of the same word will be set to tag=-1
                            if len(link_i.uids) >= len(link_j.uids):  # keep link_i
                                link_i.weight = max(link_i.weight, link_j.weight)
                                link_j.tag = -1
                            else:  # keep link_j
                                link_j.weight = max(link_i.weight, link_j.weight)
                                link_i.tag = -1
                
                dur_diff += bin_j.dur / 2
                j += 1
        
        for i, bin_i in enumerate(self.sausage.sausage_bins):
            if bin_i.size_valid() == 0:
                bin_i.add_epsilon_link(0, -1)
                bin_i.word2link[EPSILON].weight = 0
                bin_i.word2link[EPSILON].tag = 0

    def align_sausage_with_reference(self, duptime=50, maxdistance=50, frame_rate=0.01, deduplicate=True):
        duptime = int(duptime * 0.01 / frame_rate)
        maxdistance = int(maxdistance * 0.01 / frame_rate)

        ref_ali_time = 0
        sau_ali_time = 0

        # initialization
        for bin in self.sausage.sausage_bins:
            for w, link in bin.word2link.items():
                link.tag = 0

        if self.refali is not None and len(self.refali) > 0:
            # do "KWS" for each word in the alignment
            for ali in self.refali:
                w_ali, dur_ali = ali
                w_mid_time = ref_ali_time + dur_ali / 2

                if w_ali == EPSILON:
                    ref_ali_time += dur_ali
                    continue

                sau_ali_time = 0
                for i in range(len(self.sausage)):
                    bin_mid_time = sau_ali_time + self.sausage[i].dur / 2
                    if bin_mid_time - w_mid_time > maxdistance:
                        break
                    elif bin_mid_time - w_mid_time < -maxdistance:
                        sau_ali_time += self.sausage[i].dur
                        continue
                    else:   # now timing is matching
                        if w_ali in self.sausage[i]:
                            self.sausage[i][w_ali].tag = 1
                        sau_ali_time += self.sausage[i].dur
                ref_ali_time += dur_ali
        else:
            if self.ref_words is not None and len(self.ref_words) > 0:
                sm = edit_distance.SequenceMatcher(a=self.ref_words, b=self.sausage.sausage_bins, test=SausageBin.test, action_function=edit_distance.highest_match_action)
                edits = sm.get_opcodes()

                for elem in edits:
                    # logging.info(elem)
                    if elem[0] == "equal":
                        w = self.ref_words[elem[1]]
                        bin = self.sausage.sausage_bins[elem[3]]
                        for w_, link in bin.word2link.items():
                            if w == w_:
                                link.tag = 1
                            else:
                                link.tag = 0
                    elif elem[0] == "replace":
                        bin = self.sausage.sausage_bins[elem[3]]
                        for w_, link in bin.word2link.items():
                            link.tag = 0
                    elif elem[0] == "insert":
                        bin = self.sausage.sausage_bins[elem[3]]
                        for w_, link in bin.word2link.items():
                            link.tag = 0
                    elif elem[0] == "delete":
                        pass
                    else:
                        logging.error(f"Cannot reach here! elem[0]={elem[0]}")
                        exit(1)
            else:
                logging.warning(f"uid={self.uid} has empty reference words")


        # deduplicate mechanism similar to local/kws/filter_kws_results.pl
        if deduplicate:
            # self.deduplicated_weight_dependent(duptime)
            self.deduplicated_weight_independent(duptime)
        
        num_correct_tags = 0
        list_correct_tags = list()
        for i, bin in enumerate(self.sausage.sausage_bins):
            for w, link in bin.word2link.items():
                if link.tag == 1:
                    num_correct_tags += 1
                    list_correct_tags.append((i, w))
        # if num_correct_tags != len(self.ref_words):
        #     logging.info(f"{self.uid}:\n tags({num_correct_tags}): {list_correct_tags}\n ref ({len(self.ref_words)}): {self.ref_words}")

    def align_sausage_with_ref_ali(self, frame_rate=0.01):
        factor = frame_rate / 0.01

        data_points = []
        ref_ali_equal_cnt = 0
        ref_ali_cnt = 0
        if self.refali is not None and len(self.refali) > 0:
            new_refali = []
            cur_time = 0
            for ali in self.refali:
                w_ali, dur_ali = ali
                if w_ali != EPSILON:
                # if True:
                    new_refali.append((w_ali, cur_time + dur_ali / 2))  # (word, midtime)
                cur_time += dur_ali

            cur_time = 0
            for bin in self.sausage.sausage_bins:
                bin.t = cur_time + bin.dur / 2
                cur_time += bin.dur

            # align sausage with ref ali
            sm = edit_distance.SequenceMatcher(
                a=[x[0] for x in new_refali], 
                b=self.sausage.sausage_bins, 
                test=SausageBin.test, 
                action_function=edit_distance.highest_match_action
            )
            edits = sm.get_opcodes()

            ref_ali_cnt = len(new_refali)
            ref_ali_equal_cnt = 0
            for elem in edits:
                # logging.info(elem)
                if elem[0] == "equal": # or elem[0] == "replace":
                    cur_ref_ali = new_refali[elem[1]]
                    cur_bin = self.sausage.sausage_bins[elem[3]]
                    # diff = (cur_bin.t - cur_ref_ali[1]) * frame_rate   # in seconds
                    diff = (cur_bin.t - cur_ref_ali[1]) * factor   # in num of 0.01 frames
                    data_points.append(diff)
                    ref_ali_equal_cnt += 1
                elif elem[0] == "replace":
                    pass
                elif elem[0] == "insert":
                    pass
                elif elem[0] == "delete":
                    pass
                else:
                    logging.error(f"Cannot reach here! elem[0]={elem[0]}")
                    exit(1)

        return data_points, ref_ali_cnt, ref_ali_equal_cnt

    def print_w_scores_pos(self, fout=sys.stdout):
        for hyp in self.hyps:
            if self.sausage is not None and len(hyp) > 0:
                pos = self.sausage.get_conf_for_hyp(hyp)
            else:
                pos = []
            # pos_str = " ".join(map(lambda x: f"{x:.4f}", pos))
            pos_str = " ".join(map(lambda x: f"{x}", pos))
            print(f"{self.uid} {pos_str}", file=fout)
    
    def print_ctm(self, fout=sys.stdout, frame_rate=0.03):
        hyp = self.hyps[0]
        first_best_words = hyp.words
        first_best_conf = self.sausage.get_conf_for_hyp(hyp)
        first_best_timing = self.sausage.get_timing_for_hyp(hyp)

        for w, c, t in zip(first_best_words, first_best_conf, first_best_timing):
            # <F> <C> <BT> <DUR> word [ <CONF> ]
            w_filtered = wer_output_filter(w)
            if len(w_filtered) > 0:
                st = t[0] * frame_rate
                dur = t[1] * frame_rate
                print(f"{self.uid} {1} {st:.2f} {dur:.2f} {w} {np.exp(c)} ", file=fout)


class SausageLink:
    def __init__(self, word=None, weight=None, weights=None, uids=None, tag=None):
        self.word = word
        self.weight = weight   # final weight, computed from self.weights
        self.weights = weights
        self.uids = uids
        self.tag = tag
        self.i = -1
    
    def finalize_weight(self, func=logsumexp):
        # func takes an array/list as input and output an aggregation
        if len(self.weights) == 0:
            self.weight = -np.inf
            return -np.inf
        else:
            self.weight = func(self.weights)
            return self.weight

    # @classmethod
    # def epsilon(cls, weight=-np.inf):
    #     s = SausageLink(word=EPSILON, weight=weight)
    #     return s
    
    def __str__(self):
        return f"word={self.word} weight={self.weight} uids={self.uids} weights={self.weights}"


class SausageBin:
    def __init__(self, word2link=dict(), w=None, score=-np.inf, dur=1, uid=None, place_holder=False):
        self.dur = dur  # duration as the number of frames
        self.t = -1  # time (accumulated duration) as the number of frames
        if w is not None:
            self.word2link = dict()
            weights = [] if place_holder else [score]
            self.word2link[w] = SausageLink(word=w, weights=weights, uids=[])
            if uid is not None:
                self.word2link[w].uids.append(uid)
        else:
            self.word2link = word2link
    
    # def add_link(self, link):
    #     if link.w not in self:
    #         self.word2link[link.w] = link
    #     else:
    #         mylink = self.word2link[link.w]
    #         mylink.weights.append(link.weight)
    #         mylink.uids.append(link.uids[0])
    
    def add_word_link(self, word, score, uid, place_holder=False):
        if word not in self:
            weights = [] if place_holder else [score]
            self.word2link[word] = SausageLink(word, weights=weights, uids=[uid])
        else:
            mylink = self.word2link[word]
            if not place_holder:
                mylink.weights.append(score)
            mylink.uids.append(uid)
        return self
    
    def add_epsilon_link(self, score, uid, place_holder=False):
        if EPSILON not in self:
            weights = [] if place_holder else [score]
            self.word2link[EPSILON] = SausageLink(EPSILON, weights=weights, uids=[uid])
        else:
            mylink = self.word2link[EPSILON]
            if not place_holder:
                mylink.weights.append(score)
            mylink.uids.append(uid)
        return self
    
    def get_weight(self, func=logsumexp):
        scores = []
        for w, link in self.word2link.items():
            scores.append(link.finalize_weight(func=func))
        return func(scores)

    def get_uids(self):
        uids = list()
        for w, link in self.word2link.items():
            uids.extend(link.uids)
        return uids

    def __contains__(self, word):
        return word in self.word2link
    
    def __getitem__(self, w):
        return self.word2link[w]

    def __len__(self):
        return len(self.word2link)

    def size(self):
        return len(self.word2link)

    def size_valid(self):
        cnt = 0
        for w, link in self.word2link.items():
            # if link.tag == -1, this link is regarded as "not existing", as it will never show up in KWS results by rules
            if link.tag == 1 or link.tag == 0:
                cnt += 1
        # assert cnt > 0
        return cnt

    def __str__(self):
        return '\n' + '\n'.join(map(lambda x: str(x), self.word2link.values()))

    @classmethod
    def test0(cls, a, b):
        assert (isinstance(a, SausageBin) and isinstance(b, str)) or \
            (isinstance(a, str) and isinstance(b, SausageBin))

        # TODO implement some approximate match here?
        if isinstance(a, SausageBin):
            return b in a
        if isinstance(b, SausageBin):
            return a in b

    @classmethod
    def test1(cls, a, b):
        assert (isinstance(a, SausageBin) and isinstance(b, str)) or \
            (isinstance(a, str) and isinstance(b, SausageBin))

        # return a "cost", where cost=0 means a perfect match, while cost=1 means not matched
        if isinstance(a, SausageBin):
            if b in a:  # matched
                return 0 - len(a.word2link[b].uids) / 1000   # the more uids, the better
            else:
                # li = [len(link.uids) for w, link in a.word2link.items() if w != EPSILON]
                # bonus = max(li + [0])
                # return 1 - bonus / 1000   # the more uids, the better
                return 1
        if isinstance(b, SausageBin):
            if a in b:
                return 0 - len(b.word2link[a].uids) / 1000   # the more uids, the better
            else:
                # li = [len(link.uids) for w, link in b.word2link.items() if w != EPSILON]
                # bonus = max(li + [0])
                # return 1 - bonus / 1000   # the more uids, the better
                return 1
        
        # other heuristics ideas for tie breaking:
        # 1. the duration of the bin (the larger the better match?)
        # 2. the index of the bin (prefer earlier bins?)

    @classmethod
    def test(cls, a, b):
        assert (isinstance(a, SausageBin) and isinstance(b, str)) or \
            (isinstance(a, str) and isinstance(b, SausageBin))

        if isinstance(b, SausageBin):
            temp = a
            a = b
            b = temp
        
        # Now check: 
        # (1) if string "b" is in bin "a"? 
        # (2) if so, how well is it matched? 
        # (3) if not, how close are they?

        # Return a "cost", where cost=0 means a perfect match, while cost=1 means not matched
        if b in a:  # matched
            return 0 - len(a.word2link[b].uids) / 1000   # the more uids, the better
        else:
            # li = [len(link.uids) for w, link in a.word2link.items() if w != EPSILON]
            # bonus = max(li + [0])
            # return 1 - bonus / 1000   # the more uids, the better

            # consider string similarity between "b" and "w"
            li = [string_sim(w, b) for w, link in a.word2link.items() if w != EPSILON]
            bonus = max(li + [0])
            return 1 - bonus / 10


# https://stackoverflow.com/questions/17388213/find-the-similarity-metric-between-two-strings
# https://www.geeksforgeeks.org/jaro-and-jaro-winkler-similarity/
# https://jamesturk.github.io/jellyfish/functions/
def string_sim(str1, str2, oov="<unk>"):
    if str1 == str2:
        return 1
    if str1 == oov:
        return 0.8 + len(str2)/1000  # longer strings have a bonus to match <unk>
    if str2 == oov:
        return 0.8 + len(str1)/1000
    return jaro_distance(str1, str2)


class Sausage:
    def __init__(self, hyp=None, ali=None, place_holder=False):
        self.sausage_bins = list()
        if hyp is not None:
            if place_holder:
                self.from_hyp_as_ali(hyp, place_holder=place_holder)
            else:
                self.from_hyp(hyp, place_holder=place_holder)
        elif ali is not None:
            self.from_ali(ali, place_holder=place_holder)
    
    def __str__(self) -> str:
        ret = ""
        for i, bin in enumerate(self.sausage_bins):
            ret += f"{i}-th bin:\n"
            ret += str(bin)
            ret += "\n"
        return ret
    
    def show_bins(self):
        return [list(b.word2link.keys()) for b in self.sausage_bins]
    
    def __getitem__(self, i):
        return self.sausage_bins[i]
    
    def __len__(self):
        return len(self.sausage_bins)

    def from_ali(self, ali, place_holder=False):
        self.sausage_bins = [SausageBin(w=w_t[0], score=-np.inf, dur=w_t[1], place_holder=place_holder) for w_t in ali]
    
    def from_hyp_as_ali(self, hyp, place_holder=False):
        self.sausage_bins = [SausageBin(w=w, score=-np.inf, dur=1, place_holder=place_holder) for w in hyp.words]

    def from_hyp(self, hyp, place_holder=False):
        self.sausage_bins = [SausageBin(w=w, score=-np.inf, dur=len(w), uid=hyp.rank, place_holder=place_holder) for w in hyp.words]

    def add_hyp(self, hyp, score_type):
        # minimum number of edits:
        # sm = edit_distance.SequenceMatcher(a=hyp, b=self.sausage_bins, test=SausageBin.test)
        # maximum number of matches
        sm = edit_distance.SequenceMatcher(a=hyp.words, b=self.sausage_bins, test=SausageBin.test, action_function=edit_distance.highest_match_action)
        edits = sm.get_opcodes()
        # logging.info(f"{hyp.words} {hyp.utterance_score}")
        # logging.info(edits)
        # TODO: we may make this alignment better, with some rules/heuristics

        # debug:
        # hyp.words
        # self.show_bins()
        # [[elem[0], hyp.words[elem[1]], self.sausage_bins[elem[3]].word2link.keys()] for elem in edits]

        # Turn hyp into self.sausage_bins according to edits
        # For information about edits:
        # https://docs.python.org/2/library/difflib.html#difflib.SequenceMatcher.get_opcodes
        prev_total_score = self.sausage_bins[-1].get_weight(func=logsumexp) if score_type == "_pos" else -np.inf
        prev_uids = self.sausage_bins[-1].get_uids()
        new_bins = list()
        for elem in edits:
            # logging.info(elem)
            if elem[0] == "equal" or elem[0] == "replace":
                i = elem[1]
                score = hyp.utterance_score if score_type == "_pos" else hyp.words_scores[i]
                bin = self.sausage_bins[elem[3]]
                new_bin = bin.add_word_link(hyp.words[i], score, hyp.rank)
                new_bins.append(new_bin)
            elif elem[0] == "insert":
                i = elem[1]
                score = hyp.utterance_score if score_type == "_pos" else -np.inf
                bin = self.sausage_bins[elem[3]]
                new_bin = bin.add_epsilon_link(score, hyp.rank)
                new_bins.append(new_bin)
            elif elem[0] == "delete":
                i = elem[1]
                score = hyp.utterance_score if score_type == "_pos" else hyp.words_scores[i]
                new_bin = SausageBin(w=EPSILON, score=prev_total_score, dur=1)
                new_bin.word2link[EPSILON].uids = prev_uids
                new_bin = new_bin.add_word_link(hyp.words[i], score, hyp.rank)
                new_bins.append(new_bin)
            else:
                logging.error(f"Cannot reach here! elem[0]={elem[0]}")
                exit(1)

        self.sausage_bins = new_bins

        return self

    def get_conf_for_hyp(self, hyp):
        i = 0
        conf = list()
        for w in hyp.words:
            # Find a link for this word w
            while True:
                link = self.sausage_bins[i].word2link.get(w, None)
                if link is not None:
                    if hyp.rank in link.uids:
                        conf.append(link.weight)
                        i += 1
                        break
                # link is None or hyp.rank is not in link.uids
                link = self.sausage_bins[i].word2link.get(EPSILON, None)
                if link is not None and hyp.rank in link.uids:
                    i += 1
                    continue
                else:
                    logging.error(str(hyp))
                    logging.error("You cannot reach here because each hypothesis must go through a link")
                    exit(1)
                    
        assert len(conf) == len(hyp), f"{len(conf)} != {len(hyp)}, {hyp}"
        return conf
    

    def get_timing_for_hyp(self, hyp):
        i = 0
        t = 0
        timing = list()  # (start_time, duration) in terms of #frames
        for w in hyp.words:
            # Find a link for this word w
            while True:
                link = self.sausage_bins[i].word2link.get(w, None)
                if link is not None:
                    if hyp.rank in link.uids:
                        timing.append((t, self.sausage_bins[i].dur))
                        t += self.sausage_bins[i].dur
                        i += 1
                        break
                # link is None or hyp.rank is not in link.uids
                link = self.sausage_bins[i].word2link.get(EPSILON, None)
                if link is not None and hyp.rank in link.uids:
                    t += self.sausage_bins[i].dur
                    i += 1
                    continue
                else:
                    logging.error(str(hyp))
                    logging.error("You cannot reach here because each hypothesis must go through a link")
                    exit(1)
                    
        assert len(timing) == len(hyp), f"{len(timing)} != {len(hyp)}, {hyp}"
        return timing
        

    def finalize_weight(self, score_type):
        for bin in self.sausage_bins:
            for w, link in bin.word2link.items():
                if score_type == "_pos":
                    link.finalize_weight(func=logsumexp)
                else:
                    # TODO: taking mean in the log domain wihtout normalization may have problem
                    # TODO: tune this
                    link.finalize_weight(func=log_mean)
                    # link.finalize_weight(func=mean)  
                    # link.finalize_weight(func=gmean)
                    # link.finalize_weight(func=max)
                    # link.finalize_weight(func=min)
    
    def get_timing(self, dur, frame_rate=0.01):
        num_frames = int(dur / frame_rate)

        # nchars[i] will be the length of best word in this bin
        nchars = [bin.dur for bin in self.sausage_bins]
        nchars = np.asarray(nchars)

        time_lengths = nchars / nchars.sum() * num_frames
        time_lengths[time_lengths < 1] = 1
        time_lengths = np.rint(time_lengths).astype(np.int32)

        frames_remained = num_frames - time_lengths.sum()
        if frames_remained > 0:
            time_lengths[:frames_remained] += 1
        elif frames_remained < 0:
            time_lengths[np.argwhere(time_lengths > 1)[:-frames_remained]] -= 1

        for bin, t in zip(self.sausage_bins, time_lengths):
            bin.dur = t
        return time_lengths


    def stats(self):
        nbins = len(self.sausage_bins)
        nlinks = 0
        for bin in self.sausage_bins:
            nlinks += len(bin.word2link)
        return nbins, nlinks
    
    def print_as_compact_lattice(self, uid, fout=sys.stdout):
        print(uid, file=fout)
        for cur_state_id, bin in enumerate(self.sausage_bins):
            for w, link in bin.word2link.items():
                trans_ids = "_".join(["1"] * bin.dur)
                if link.weight < -10000:
                    link.weight = -10000
                cost = "{:.4e}".format(-link.weight)
                output_line = f'{cur_state_id} {cur_state_id + 1} {w} {0},{cost},{trans_ids}'
                if not opts.quiet:
                    logging.info(output_line)
                print(output_line, file=fout)
        output_line = f'{cur_state_id + 1} 0,0,'
        if not opts.quiet:
            logging.info(output_line)
        print(output_line, file=fout)
        print("", file=fout)
    
    def print_as_htk_lattice(self, uid, basedir, frame_rate=0.03):
        # format: http://www.seas.ucla.edu/spapl/weichu/htkbook/node460_mn.html
        #         http://www.seas.ucla.edu/spapl/weichu/htkbook/node457_mn.html
        # Note: we need to convert the "links" in our sausages to "nodes" in the htk lattices

        # logging.info(f"uid={uid}")

        target = [1]
        indices = [0]
        ref = [1]   # assert len(ref) == len(indices)
        def append_arcs(j, link):
            assert link.tag == 0 or link.tag == 1
            target.append(link.tag)
            if 0 in link.uids:
                indices.append(j)
                ref.append(link.tag)
        
        filename = Path(basedir) / "lattices" / f"{uid}.lat.gz"
        if not filename.parent.exists():
            try:
                os.mkdir(filename.parent)
            except:
                logging.info(f"Please check if {filename.parent} exits")
        with gzip.open(filename, 'wt', encoding='utf-8') as fout:
            # latticehead
            fout.write("VERSION=1.0\n")
            fout.write(f"UTTERANCE={uid}\n")
            fout.write("SUBLAT=x\n")
            fout.write("lmname=x\n")
            fout.write("lmscale=x\n")
            fout.write("prscale=x\n")
            fout.write("acscale=x\n")
            fout.write("vocab=x\n")   # HEADER_LINE_COUNT

            # lattice
            # sizespec
            nlinks = [1] + [1] + [b.size_valid() for b in self.sausage_bins] + [1]
            N = sum(nlinks)
            # L = sum([nlinks[i] * nlinks[i + 1] for i in range(len(nlinks) - 1)])
            L = sum([i1 * i2 for i1, i2 in zip(nlinks[:-1], nlinks[1:])])
            fout.write(f"N={N} L={L}\n")
            logging.info(f"uid:{uid} N={N} L={L}")

            # node
            i = 0
            t = 0
            nodes = list()
            nodes.append((i, t, "!NULL")); i += 1
            nodes.append((i, t, "<s>")); i += 1
            for bin in self.sausage_bins:
                for w, link in bin.word2link.items():
                    if link.tag == 0 or link.tag == 1:
                        link.i = i   # give each link an index number
                        nodes.append((i, t, w)); i += 1                        
                t += bin.dur
            nodes.append((i, t, "</s>")); i += 1
            assert i == N
            for nn in nodes:
                fout.write(f"I={nn[0]} t={nn[1] * frame_rate:.2f} W={nn[2]} v=1\n")

            # arc
            j = 0
            arcs = list()
            arcs.append((j, 0, 1, 0.0)); j += 1
            # sos
            bin_sos = SausageBin(w="<s>", uid=1, place_holder=True)
            bin_sos.word2link["<s>"].i = 1
            bin_sos.word2link["<s>"].tag = 1
            # eos
            bin_eos = SausageBin(w="</s>", uid=1, place_holder=True)
            bin_eos.word2link["</s>"].i = N - 1
            bin_eos.word2link["</s>"].tag = 1
            bin_eos.word2link["</s>"].weight = 0.0
            bin_eos.word2link["</s>"].uids = [0]
            # binlist
            binlist = [bin_sos] + self.sausage_bins + [bin_eos]
            for bin1, bin2 in zip(binlist[:-1], binlist[1:]):
                for w1, link1 in bin1.word2link.items():
                    if not(link1.tag == 0 or link1.tag == 1):
                        continue
                    for w2, link2 in bin2.word2link.items():
                        if link2.tag == 0 or link2.tag == 1:
                            append_arcs(j, link2)
                            arcs.append((j, link1.i, link2.i, link2.weight, link2)); j += 1
            assert j == L, f"j={j}, L={L}"
            for aa in arcs:
                if aa[3] is None:
                    print("len(arcs)=%d" % (len(arcs)))
                    print(vars(aa[4]))
                fout.write(f"J={aa[0]} S={aa[1]} E={aa[2]} p={max(aa[3], -200)}\n")
        
        filename = Path(basedir) / "target" / f"{uid}.npz"
        if not filename.parent.exists():
            os.mkdir(filename.parent)
        target = np.array(target, dtype=float)
        indices = np.array(indices, dtype=int)
        ref = np.array(ref, dtype=float)
        np.savez(filename, target=target, indices=indices, ref=ref)

    def print_as_npz_lattice(self, uid, basedir, frame_rate=0.03):
        # format: 
        # https://github.com/alecokas/BiLatticeRNN-data-processing/blob/master/data-processing-scripts/preprocess_lattices.py#L126
        # https://github.com/alecokas/BiLatticeRNN-data-processing/blob/master/data-processing-scripts/preprocess_lattices.py#L24

        nodes = []
        edges = []
        dependency = defaultdict(set)
        child_2_parent = defaultdict(set)
        parent_2_child = defaultdict(set)

        # node_num = len(self.sausage_bins) + 1
        # edge_num = sum([b.size_valid() f or b in self.sausage_bins])

        target = []
        indices = []
        ref = []   # assert len(ref) == len(indices)
        def append_arcs(j, link):
            assert link.tag == 0 or link.tag == 1
            target.append(link.tag)
            if 1 in link.uids:  # 1st best hypo
                indices.append(j)
                ref.append(link.tag)

        # populate nodes
        t = 0
        for cur_state_id, bin in enumerate(self.sausage_bins):
            nodes.append([t, None])
            t += bin.dur * frame_rate
        nodes.append([t, None])

        # populate edges
        link_i = 0
        for cur_state_id, bin in enumerate(self.sausage_bins):
            for word, link in bin.word2link.items():
                if not(link.tag == 0 or link.tag == 1):    # TODO: why?
                    continue

                link.i = link_i   # give each link an index number
                link_i += 1

                edge_id = link.i
                parent = cur_state_id
                child = cur_state_id + 1
                # score = link.weight   # TODO: which option is good?
                score = np.exp(link.weight)
                assert score >= -1e-4 and score < 1 + 1e-4
                # if score < -10000:
                #     score = -10000

                edges.append([parent, child, score, word, bin.dur * frame_rate])
                append_arcs(edge_id, link)

                dependency[child].add(parent)
                child_2_parent[child].add((parent, edge_id))
                parent_2_child[parent].add((child, edge_id))

        # save multiple variables into one .npz file
        # filename = Path(basedir) / "lattices" / f"{uid}.lat.gz"
        suffix = uid[-3:]
        filename = Path(basedir) / "lattices" / suffix / f"{uid}.lat.gz"
        if not filename.parent.exists():
            try:
                os.makedirs(filename.parent, exist_ok=True)
            except:
                logging.info(f"Please check if {filename.parent} exits")
        # http://henrysmac.org/blog/2010/3/15/python-pickle-example-including-gzip-for-compression.html
        with gzip.open(filename, 'wb') as fout:
            dump_obj = {
                "nodes": nodes, 
                "edges": edges, 
                "dependency": dependency, 
                "child_2_parent": child_2_parent, 
                "parent_2_child": parent_2_child
            }
            pickle.dump(dump_obj, fout)

        # save targets
        filename = Path(basedir) / "target" / suffix / f"{uid}.npz"
        if not filename.parent.exists():
            os.makedirs(filename.parent, exist_ok=True)
        target = np.array(target, dtype=float)
        indices = np.array(indices, dtype=int)
        ref = np.array(ref, dtype=float)
        assert len(ref) == len(indices)
        assert len(ref) > 0
        np.savez(filename, target=target, indices=indices, ref=ref)

        logging.info(f"Done: {filename}")

    def set_confidence(self, my_confidence):
        # loop over edges
        link_i = 0
        for cur_state_id, bin in enumerate(self.sausage_bins):
            for word, link in bin.word2link.items():
                if not(link.tag == 0 or link.tag == 1):    # TODO: why?
                    continue
                
                link.i = link_i   # give each link an index number
                link_i += 1

                edge_id = link.i
                score = my_confidence[edge_id]
                assert score >= -1e-4 and score < 1 + 1e-4
                link.weight = np.log(score).item()

    def instrinsic_confidence_eval(self, keywords):
        predictions = []
        labels = []
        predictions_onebest = []
        labels_onebest = []
        predictions_restricted = []
        labels_restricted = []
        word_list = []
        # one_best_flag = 1 in link.uids if one_best else True   # 1st best hypo and

        # phrases should be broken down to words
        keywords_set = set()
        for word in keywords:
            for w in word.split():
                keywords_set.add(w)
            
        for cur_state_id, bin in enumerate(self.sausage_bins):
            for word, link in bin.word2link.items():
                score = np.exp(link.weight)  # prob between 0 and 1
                label = link.tag
                
                if label != 0 and label != 1:
                    continue

                if word == EPSILON or word == EPSILON2 or len(wer_output_filter(word)) == 0:
                    continue

                predictions.append(score)
                labels.append(label)
                if 1 in link.uids: # 1st best hypo
                    predictions_onebest.append(score)
                    labels_onebest.append(label)
                
                if word in keywords_set:
                    predictions_restricted.append(score)
                    labels_restricted.append(label)
                
                word_list.append(word)
        return predictions, labels, predictions_onebest, labels_onebest, predictions_restricted, labels_restricted, word_list


    def print_as_links(self, uid, fout=sys.stdout):
        print(uid, file=fout)
        dur = 0
        for cur_state_id, bin in enumerate(self.sausage_bins):
            for w, link in bin.word2link.items():
                if w == EPSILON:
                    continue

                # These words will not be scored or searched, so we will not consider them
                w_filtered = wer_output_filter(w)
                if len(w_filtered) == 0:
                    continue

                if link.tag == -1 or link.tag == None:
                    continue

                if link.weight < -10000:
                    logging.error(f"{uid}, state:{cur_state_id}, {w}:{link.weight}")
                    link.weight = -10000

                # output_line = f'{w} {link.weight} {link.tag}'
                output_line = f'{w} {link.weight} {link.tag} ({dur}, {dur + bin.dur})'
                if not opts.quiet:
                    logging.info(output_line)
                print(output_line, file=fout)
            dur += bin.dur
        print("", file=fout)


def load_prediction(filename):
    x = np.load(filename, allow_pickle=True)
    x = x['prediction']
    x = x.flatten()[0]
    return x


def main(opts):
    uid2utt = Utterance.read_nbest_list(opts)

    if opts.confidence is not None:
        logging.info(f"Using confidence from {opts.confidence}")
        uid2confidence = load_prediction(opts.confidence)

    for uid, utt in uid2utt.items():
        # if uid == "en_6265_0B_00097":
        local_score_type = opts.score_type if opts.score_type != "_conf" else "_pos"
        sau = utt.build_sausage_from_nbest(score_type=local_score_type, nsize=opts.nsize)
        if opts.confidence is not None:
            # TODO: this one will change the sausage structure by adding additional eps arcs
            # They should be un-do when saving as compact lattices
            utt.align_sausage_with_reference(duptime=60, maxdistance=50, frame_rate=0.01, deduplicate=True)  # because we need to know the tags of the links -- to infer edge id 
            if uid in uid2confidence:
                try:
                    sau.set_confidence(uid2confidence[uid])
                except:
                    logging.error(f"uid={uid} does not have confidence")
            else:
                logging.error(f"uid={uid} does not have confidence")
        if sau is not None and not opts.no_print_sausage:
            # TODO: need to un-do the extra eps arcs due to "align_sausage_with_reference"
            sau.print_as_compact_lattice(uid)
    
    if (opts.score_type == "_pos" or opts.score_type == "_conf") and opts.print_w_pos:
        pos_path = Path(opts.workdir) / f"nbest_w_scores{opts.score_type}_{opts.scale}.txt"
        with open(pos_path, "w") as fout:
            logging.info(f"Saving pos scores to: {pos_path}")
            for uid, utt in uid2utt.items():
                utt.print_w_scores_pos(fout=fout)

    if opts.ctm is not None:
        with open(opts.ctm, "w") as fout:
            logging.info(f"Saving ctm files for the first best to: {opts.ctm}")
            for uid, utt in uid2utt.items():
                utt.print_ctm(fout=fout, frame_rate=0.01)
    
    if opts.data_points is not None:
        with open(opts.data_points, "w") as fout:
            logging.info(f"Saving data points to: {opts.data_points}")
            for uid, utt in uid2utt.items():
                utt.align_sausage_with_reference(duptime=60, maxdistance=50, frame_rate=0.01)   # we have to set duptime to 60...
                utt.sausage.print_as_links(uid, fout=fout)

    if opts.htk_lattice_dir is not None:
        if not Path(opts.htk_lattice_dir).exists():
            os.mkdir(opts.htk_lattice_dir)
        for uid, utt in uid2utt.items():
            utt.align_sausage_with_reference(duptime=60, maxdistance=50, frame_rate=0.01, deduplicate=False)   # we have to set duptime to 60...
            utt.sausage.print_as_htk_lattice(uid, opts.htk_lattice_dir, frame_rate=0.01)

    if opts.npz_lattice_dir is not None:
        if not Path(opts.npz_lattice_dir).exists():
            os.mkdir(opts.npz_lattice_dir)
        for uid, utt in uid2utt.items():
            utt.align_sausage_with_reference(duptime=60, maxdistance=50, frame_rate=0.01, deduplicate=True)   # we have to set duptime to 60...
            utt.sausage.print_as_npz_lattice(uid, opts.npz_lattice_dir, frame_rate=0.01)

    if opts.intrinsic_conf:
        keywords = load_keywords(opts)

        predictions = list()
        labels = list()
        predictions_onebest = list()
        labels_onebest = list()
        predictions_restricted = list()
        labels_restricted = list()
        word_list = list()

        logging.info("Compute intrinsic evals...")
        for uid, utt in uid2utt.items():
            utt.align_sausage_with_reference(duptime=60, maxdistance=50, frame_rate=0.01, deduplicate=True)   # we have to set duptime to 60...
            
            predictions_, labels_, predictions_onebest_, labels_onebest_, predictions_restricted_, labels_restricted_, word_list_ = utt.sausage.instrinsic_confidence_eval(keywords)
            predictions.extend(predictions_)
            labels.extend(labels_)
            predictions_onebest.extend(predictions_onebest_)
            labels_onebest.extend(labels_onebest_)
            predictions_restricted.extend(predictions_restricted_)
            labels_restricted.extend(labels_restricted_)
            word_list.extend(word_list_)

        predictions = np.asarray(predictions)
        labels = np.asarray(labels)
        predictions_onebest = np.asarray(predictions_onebest)
        labels_onebest = np.asarray(labels_onebest)
        predictions_restricted = np.asarray(predictions_restricted)
        labels_restricted = np.asarray(labels_restricted)
        
        filename = Path(opts.workdir) / f"conf_eval_{opts.score_type}_{opts.scale}.npz"
        np.savez(filename, 
            predictions=predictions, labels=labels, 
            predictions_onebest=predictions_onebest, labels_onebest=labels_onebest,
            predictions_restricted=predictions_restricted, labels_restricted=labels_restricted, 
            wordlist=word_list, keywords=keywords)
        logging.info(f"Done: {filename}")

    if opts.intrinsic_time:
        data_points = []
        ref_ali_cnt = 0 
        ref_ali_equal_cnt = 0
        for uid, utt in uid2utt.items():
            data_points_, ref_ali_cnt_, ref_ali_equal_cnt_ = utt.align_sausage_with_ref_ali(frame_rate=0.01)
            data_points.extend(data_points_)
            ref_ali_cnt += ref_ali_cnt_
            ref_ali_equal_cnt += ref_ali_equal_cnt_
        
        filename = Path(opts.workdir) / f"time_eval.npz"
        np.savez(
            filename, 
            data_points=data_points,
            ref_ali_cnt=ref_ali_cnt,
            ref_ali_equal_cnt=ref_ali_equal_cnt
        )
        logging.info(f"Done: {filename}")


    logging.info(f"Done {len(uid2utt)} sausages")    


if __name__ == '__main__':
    opts = parse_opts()
    EPSILON = opts.eps
    UNK = opts.oov

    main(opts)

# Test cases:
#
# cat > tmp5.txt <<EOF
# u001 -1 a b c d
# u001 -1 a b c d
# u001 -3 a b d
# u001 -5 a b
# u001 -7 a b e c d
# u001 -11 e a b e c d
# EOF
# 
# python3 rover.py --nbest tmp5.txt --dur <(echo "u001 4")
