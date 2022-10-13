from collections import defaultdict
from collections import Counter
import logging
import argparse
from glob import glob
import statistics

from attr import field
from check_cm_distribution import wer_output_filter


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--nbest', type=str, default=None, help='')
    parser.add_argument('--nbest_distribution', action='store_true', help='')
    parser.add_argument('--oracle_wer', action='store_true', help='')
    parser.add_argument('--nj', type=int, default=32, help='')
    parser.add_argument('--per_utt', type=str, default=None, help='')
    parser.add_argument('--n', type=int, default=1, help='size of the nbest list')
    parser.add_argument('--convert_kaldi', action='store_true', help='')
    parser.add_argument('--text', type=str, default=None, help='')

    opts = parser.parse_args()
    logging.info(f"Parameters: {vars(opts)}")
    return opts


def read_text(filename):
    utt2text = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            uid = fields[0]
            dur = fields[1:]
            utt2text[uid] = dur
    logging.info("len(utt2text)=%d" % len(utt2text))
    return utt2text


def nbest_distribution(opts):
    files = glob(opts.nbest)
    logging.info("There are %d files" % len(files))

    uid_nbest_count = defaultdict(lambda: 0)
    for f in files:
        with open(f, "r") as fin:
            for line in fin:
                line = line.strip()
                if len(line) == 0:
                    continue
                line = line.split(maxsplit=2)
                
                uid = line[0]
                # uid = uid[:uid.rindex("-")]
                score = float(line[1])
                if len(line) > 2:
                    sent = line[2]
                else:
                    sent = ""
                
                if uid_nbest_count[uid] >= opts.n:
                    continue
                uid_nbest_count[uid] += 1
    
    counts = Counter(uid_nbest_count.values())
    logging.info(opts.nbest)
    logging.info(f"size of n-best: {opts.n}")
    logging.info(sorted(counts.items()))
    logging.info(f"mean: {statistics.mean(uid_nbest_count.values())}")
    logging.info(f"mode: {statistics.mode(uid_nbest_count.values())}")
    logging.info(f"stdev: {statistics.stdev(uid_nbest_count.values())}")
    logging.info(f"min: {min(uid_nbest_count.values())}")
    logging.info(f"max: {max(uid_nbest_count.values())}")

    return counts


def number_of_distinct_words(opts, apply_filter=False):
    files = glob(opts.nbest)
    logging.info("There are %d files" % len(files))

    uid_words = defaultdict(set)
    uid_cnt = defaultdict(int)
    for f in files:
        with open(f, "r") as fin:
            for line in fin:
                line = line.strip()
                if len(line) == 0:
                    continue
                line = line.split(maxsplit=2)
                
                uid = line[0]
                # uid = uid[:uid.rindex("-")]
                score = float(line[1])

                uid_cnt[uid] += 1
                if uid_cnt[uid] > opts.n:
                    continue

                if len(line) > 2:
                    sent = line[2]
                    if apply_filter:
                        sent = wer_output_filter(sent)
                else:
                    sent = ""
                
                uid_words[uid].update(sent.split())
    return uid_words


def set_of_words(opts, apply_filter=False):
    uid_text = read_text(opts.text)
    uid_words = number_of_distinct_words(opts, apply_filter=apply_filter)

    set_of_words_stats = dict()
    for uid, txt in uid_text.items():
        txt = " ".join(txt)
        if uid not in uid_words:
            set_of_words_stats[uid] = (None, None)
        else:
            if apply_filter:
                txt = wer_output_filter(txt)
            txt = set(txt.split())
            nbest = uid_words[uid]

            overlap = txt.intersection(nbest)
            precision = None if len(nbest) == 0 else len(overlap) / len(nbest)
            recall = None if len(txt) == 0 else len(overlap) / len(txt)
            set_of_words_stats[uid] = (precision, recall)
    return set_of_words_stats


# https://www.geeksforgeeks.org/python-multiset/
def bag_of_words(opts, apply_filter=False):
    uid_text = read_text(opts.text)
    uid_words = number_of_distinct_words(opts, apply_filter=apply_filter)

    bag_of_words_stats = dict()
    for uid, txt in uid_text.items():
        txt = " ".join(txt)
        if uid not in uid_words:
            bag_of_words_stats[uid] = (None, None)
        else:
            if apply_filter:
                txt = wer_output_filter(txt)
            txt = set(txt.split())
            nbest = uid_words[uid]

            overlap = txt.intersection(nbest)
            precision = None if len(nbest) == 0 else len(overlap) / len(nbest)
            recall = None if len(txt) == 0 else len(overlap) / len(txt)
            set_of_words_stats[uid] = (precision, recall)
    return set_of_words_stats



def get_oracle_wer(opts):
    if opts.text is not None:
        uid_text = read_text(opts.text)
        checkuid = lambda uid: uid in uid_text
    else:
        checkuid = lambda uid: True

    # logging.info(f"Parameters: {vars(opts)}")

    files = glob(opts.per_utt)
    logging.info("There are %d files" % len(files))
    utt2csid_list = defaultdict(list)
    utt2wer = dict()
    utt2oracle_wer = dict()
    uid_nbest_count = defaultdict(lambda: 0)
    for f in files:
        with open(f, "r") as fin:
            for line in fin:
                line = line.strip()
                if len(line) == 0:
                    continue
            
                fields = line.split()
                if fields[1] != "#csid":
                    continue
            
                uid = fields[0][: fields[0].rindex("-")]
                c = int(fields[2])
                s = int(fields[3])
                i = int(fields[4])
                d = int(fields[5])

                # if c + s + d == 0:
                #     logging.warning(f"{line}")
                #     continue

                if not checkuid(uid):
                    # logging.info(line)
                    continue

                n_errors = s + i + d 
                n_ref = c + s + d
                # wer = (s + i + d) / (c + s + d)

                if uid not in utt2wer:
                    utt2wer[uid] = (n_errors, n_ref)

                if len(utt2csid_list[uid]) < opts.n:
                    utt2csid_list[uid].append((c, s, i, d))
                    if uid not in utt2oracle_wer or utt2oracle_wer[uid][0] > n_errors:
                        utt2oracle_wer[uid] = (n_errors, n_ref)
                
                    uid_nbest_count[uid] += 1
    
    numerator = sum([werc[0] for uid, werc in utt2wer.items()])
    denominator = sum([werc[1] for uid, werc in utt2wer.items()])
    wer = numerator / denominator
    logging.info(f"WER = {wer} [{numerator}/{denominator}] ({len(utt2wer)})")

    numerator = sum([werc[0] for uid, werc in utt2oracle_wer.items()])
    denominator = sum([werc[1] for uid, werc in utt2oracle_wer.items()])
    oracle_wer = numerator / denominator
    logging.info(f"Oracle WER = {oracle_wer} [{numerator}/{denominator}] ({len(utt2oracle_wer)})")

    return utt2csid_list, utt2wer, utt2oracle_wer, uid_nbest_count


def get_precision_recall(opts):
    sow = set_of_words(opts, apply_filter=True)
    logging.info(f"len(bow) = {len(sow)}")
    
    precisions = [stat[0] for uid, stat in sow.items() if stat[0] is not None]
    recalls = [stat[1] for uid, stat in sow.items() if stat[1] is not None]
    logging.info(f"len(precisions) = {len(precisions)}, len(recalls) = {len(recalls)}")
    logging.info(f"precision: mean={statistics.mean(precisions)}, mode={statistics.mode(precisions)}, var={statistics.variance(precisions)}, min={min(precisions)}, max={max(precisions)}")
    logging.info(f"recall: mean={statistics.mean(recalls)}, mode={statistics.mode(recalls)}, var={statistics.variance(recalls)}, min={min(recalls)}, max={max(recalls)}")


def convert_kaldi_nbest(opts):
    files = glob(opts.nbest)
    logging.info("There are %d files" % len(files))  # should be one. We work on the merged file directly

    prev_uid = None
    rank = 1
    for f in files:
        with open(f, "r") as fin:
            for line in fin:
                line = line.strip()
                if len(line) == 0:
                    continue
                line = line.split(maxsplit=1)
                
                uid = line[0]
                uid = uid[:uid.rindex("-")]
                if uid != prev_uid:
                    # print(uid, prev_uid)
                    prev_uid = uid
                    rank = 1
                
                if len(line) > 1:
                    sent = line[1]
                else:
                    continue
                
                print(uid + f"-{rank}")
                print("0 1 <eps> ")
                for i, w in enumerate(sent.split()):
                    print(f"{i+1} {i+2} {w} 0,0,")
                print(f"{i + 2}\n")
                rank += 1
            

def main(opts):

    if opts.nbest_distribution:
        nbest_distribution(opts)
    if opts.oracle_wer:
        get_oracle_wer(opts)
        get_precision_recall(opts)
        nbest_distribution(opts)
    if opts.convert_kaldi:
        convert_kaldi_nbest(opts)


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
