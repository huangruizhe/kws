#!/usr/bin/env python3

import argparse
import logging

logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='This script gets the first non-empty hypothesis for each utterance from the nbest list',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--nbest', type=str, help='txt file contains lines of (uid, log-prob, hyp) pairs')
    parser.add_argument('--mfa', type=str, help='path to the corpus directory for the Montreal Forced Aligner')

    opts = parser.parse_args()
    return opts


def get_txt(opts):
    utterance_cnt = 0
    with open(opts.nbest, mode="r", encoding="utf-8") as f:
        utterance = None
        alternatives = list()
        for line in f:
            # assuming the input (nbest file) to be of this format for each line:
            # (uid, log-prob, sentence)
            # In Kaldi, the "log-prob" can be positive, but it does not matter if we normalize the posterior for each sentence

            line = line.rstrip().split()
            if len(line) == 0:
                continue

            if line[0] == utterance:
                if len(line) >= 3:  # There can be empty hypothesis in the nbest list. We will ignore them
                    alternatives.append(line[2:])
            else:
                if utterance:
                    print(utterance + '\t' + ' '.join(alternatives[0]) if len(alternatives) > 0 else '')
                    utterance_cnt += 1
                utterance = line[0]
                alternatives = list()
                if len(line) >= 3:
                    alternatives.append(line[2:])

        # don't forget the last one
        print(utterance + '\t' + ' '.join(alternatives[0]) if len(alternatives) > 0 else '')
        utterance_cnt += 1
        # logging.info(f"Done {utterance_cnt} utterances.")


def get_mfa(opts):
    def write_utt_text(path, uid, text):
        with open(path + f"/{uid}.lab", mode="w", encoding="utf-8") as fout:
            print(text, file=fout)

    utterance_cnt = 0
    with open(opts.nbest, mode="r", encoding="utf-8") as f:
        utterance = None
        alternatives = list()
        for line in f:
            # assuming the input (nbest file) to be of this format for each line:
            # (uid, log-prob, sentence)
            # In Kaldi, the "log-prob" can be positive, but it does not matter if we normalize the posterior for each sentence

            line = line.rstrip().split()
            if len(line) == 0:
                continue

            if line[0] == utterance:
                if len(line) >= 3:  # There can be empty hypothesis in the nbest list. We will ignore them
                    alternatives.append(line[2:])
            else:
                if utterance:
                    write_utt_text(opts.mfa, utterance, ' '.join(alternatives[0] if len(alternatives) > 0 else ''))
                    utterance_cnt += 1
                utterance = line[0]
                alternatives = list()
                if len(line) >= 3:
                    alternatives.append(line[2:])

        # don't forget the last one
        write_utt_text(opts.mfa, utterance, ' '.join(alternatives[0] if len(alternatives) > 0 else ''))
        utterance_cnt += 1
        logging.info(f"Done {utterance_cnt} utterances.")    


def main(opts):
    if opts.mfa is not None:
        get_mfa(opts)
    elif opts.nbest is not None:
        get_txt(opts)
    else:
        logging.error("Cannot reach here!")
        exit()

if __name__ == '__main__':
    opts = parse_opts()
    main(opts)
