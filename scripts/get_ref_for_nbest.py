# -*- coding: utf-8 -*-

import logging
import argparse
# import sentencepiece_tokenizer as st
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
    parser.add_argument('--text', type=str, help='')
    parser.add_argument('--wscores', type=str, help='')
    parser.add_argument('--cm_ali', type=str, help='')
    parser.add_argument('--ref', type=str, help='')
    parser.add_argument('--hyp', type=str, help='')
    parser.add_argument('--score_type', type=str, default="", help='')
    parser.add_argument('--get_ref', action='store_true', help='')
    parser.add_argument('--get_ref_no_scores', action='store_true', help='')
    parser.add_argument('--get_ali', action='store_true', help='')
    parser.add_argument('--get_rover2', action='store_true', help='')
    parser.add_argument('--get_tags', action='store_true', help='')
    parser.add_argument('--bpe_model', type=str, default=None, help='')
    parser.add_argument('--apply_filter', action='store_true', help='')

    opts = parser.parse_args()
    return opts


def read_text(filename):
    text = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split(maxsplit=1)
            uid = fields[0]
            if len(fields) > 1:
                sent = fields[1]
            else:
                sent = ""
            text[uid] = sent
    print("len(text)=%d" % len(text))
    return text


def get_ref(opts, text):
    cnt = 0
    with open(opts.nbest, "r") as fin_nbest, \
        open(opts.wscores, "r") as fin_wscores, \
        open(opts.hyp + ".wscores", "w") as fout_wscores, \
        open(opts.hyp, "w") as fout_hyp, \
        open(opts.ref, "w") as fout_ref:

        for ith, line in enumerate(zip(fin_nbest, fin_wscores)):
            line, line_scores = line
            line = line.strip()
            if len(line) == 0:
                continue
            
            line = line.split(maxsplit=2)
            uid = line[0]
            score = line[1]
            if len(line) > 2:
                sent = line[2]
            else:
                sent = ""

            line_scores = line_scores.strip().split(maxsplit=1)
            assert uid == line_scores[0]
            if len(line_scores) > 1:
                wscores = line_scores[1].split()
                assert len(sent.split()) == len(wscores) or sent.split()[-1] == "⁇"
                line_scores_str = line_scores[1]
            else:
                line_scores_str = ""
            
            print(f"{uid}-{ith+1} {sent}", file=fout_hyp)
            print(f"{uid}-{ith+1} {text[uid]}", file=fout_ref)
            print(f"{uid}-{ith+1} {line_scores_str}", file=fout_wscores)
            cnt += 1
    logging.info("Done %d hyps." % cnt)
    logging.info(f"Hyp: {opts.hyp}")
    logging.info(f"Ref: {opts.ref}")
    return


def get_ref_no_scores(opts, text):
    if opts.bpe_model is not None:
        sp = st.SentencepiecesTokenizer(opts.bpe_model)
        text_process_func = sp.text2tokens   # TODO: this has bug!!!
    else:
        text_process_func = lambda x: x.split()

    cnt = 0
    with open(opts.nbest, "r") as fin_nbest, \
        open(opts.hyp, "w") as fout_hyp, \
        open(opts.ref, "w") as fout_ref:

        for ith, line in enumerate(fin_nbest):
            line = line.strip()
            if len(line) == 0:
                continue
            
            line = line.split(maxsplit=2)
            uid = line[0]
            score = line[1]
            if len(line) > 2:
                sent = line[2]
            else:
                sent = ""
            
            if opts.apply_filter:
                sent = ' '.join(text_process_func(wer_output_filter(sent)))
                sent_ref = ' '.join(text_process_func(wer_output_filter(text[uid])))
            else:
                sent = ' '.join(text_process_func(sent))
                sent_ref = ' '.join(text_process_func(text[uid]))

            print(f"{uid}-{ith+1} {sent}", file=fout_hyp)
            print(f"{uid}-{ith+1} {sent_ref}", file=fout_ref)
            cnt += 1
    logging.info("Done %d hyps." % cnt)
    logging.info(f"Hyp: {opts.hyp}")
    logging.info(f"Ref: {opts.ref}")
    return        


def get_ali(opts):
    pass


def get_rover2(opts):
    base = opts.cm_ali[: opts.cm_ali.rindex("/")]
    new_nbest_file = base + "/rover2_nbest.txt"
    new_scores_file = base + f"/rover2_nbest_w_scores{opts.score_type}.txt"
    new_tag_file = base + "/rover2_nbest_tag.txt"

    with open(opts.nbest, "r") as fin_nbest, \
        open(opts.cm_ali, "r") as fin_cm_ali, \
        open(new_nbest_file, "w") as fout_nbest, \
        open(new_scores_file, "w") as fout_scores, \
        open(new_tag_file, "w") as fout_tags:

        for line1, line2 in zip(fin_nbest, fin_cm_ali):
            line1 = line1.strip().split()
            line2 = line2.strip().split(maxsplit=1)

            if len(line1) == 0:
                continue
            
            assert len(line1) >= 2
            
            uid1 = line1[0]
            uid2 = line2[0]
            uid2 = uid2[: uid2.rindex("-")]
            assert uid1 == uid2

            utt_score = line1[1]

            if len(line1) == 2:
                print(f"{uid1} {utt_score}", file=fout_nbest)
                print(f"{uid1}", file=fout_scores)
                print(f"{uid1}", file=fout_tags)
                continue

            if len(line2) == 1:   # This is possible due to the wer_output_filter
                # logging.info(f"[warning] {str(line2)}")
                print(f"{uid1} {utt_score}", file=fout_nbest)
                print(f"{uid1}", file=fout_scores)
                print(f"{uid1}", file=fout_tags)
                continue
            
            tuples = line2[1].split(",")
            tuples = [t.strip()[1:-1].split() for t in tuples if len(t.strip()) > 0]
            # (word, word_cm, utt_posterior, op)

            words_seq = " ".join([t[0] for t in tuples])
            words_cm = " ".join([t[1] for t in tuples])
            ops = " ".join([t[3] for t in tuples])
            print(f"{uid1} {utt_score} {words_seq}", file=fout_nbest)
            print(f"{uid1} {words_cm}", file=fout_scores)
            print(f"{uid1} {ops}", file=fout_tags)


def get_tags(opts):
    base = opts.nbest[: opts.nbest.rindex("/")]
    new_tag_file = base + "/nbest_tags.txt"
    with open(opts.nbest, "r") as fin_nbest, \
        open(opts.cm_ali, "r") as fin_cm_ali, \
        open(new_tag_file, "w") as fout_tags:

        for line1, line2 in zip(fin_nbest, fin_cm_ali):
            line1 = line1.strip().split()
            line2 = line2.strip().split(maxsplit=1)

            if len(line1) == 0:
                continue
            
            assert len(line1) >= 2
            
            uid1 = line1[0]
            uid2 = line2[0]
            uid2 = uid2[: uid2.rindex("-")]
            assert uid1 == uid2

            utt_score = line1[1]

            if len(line1) == 2:
                print(f"{uid1}", file=fout_tags)
                continue

            # if len(line2) == 1:   # This is possible due to the wer_output_filter
            #     # logging.info(f"[warning] {str(line2)}")
            #     print(f"{uid1}", file=fout_tags)
            #     continue
            
            tuples = line2[1].split(",")
            tuples = [t.strip()[1:-1].split() for t in tuples if len(t.strip()) > 0]
            # (word, word_cm, utt_posterior, op)

            while len(line1) > 0 and line1[-1] == "⁇":
                line1 = line1[:-1]

            assert len(line1[2:]) == len(tuples), f"{uid1} {len(line1[2:])} != {len(tuples)}, {line1[2:]}, {tuples}"

            words_seq = " ".join([t[0] for t in tuples])
            assert words_seq == " ".join(line1[2:])

            ops = " ".join([t[3] for t in tuples])

            print(f"{uid1} {ops}", file=fout_tags)    


def main(opts):

    if opts.get_ref:
        logging.info("get_ref mode")
        text = read_text(opts.text)
        get_ref(opts, text)
    elif opts.get_ali:
        logging.info("get_ali mode")
        get_ali(opts)
    elif opts.get_rover2:
        logging.info("get_rover2 mode")
        get_rover2(opts)
    elif opts.get_tags:
        logging.info("get_tags mode")
        get_tags(opts)
    elif opts.get_ref_no_scores:
        logging.info("get_ref_no_scores mode")
        text = read_text(opts.text)
        get_ref_no_scores(opts, text)
    else:
        logging.info("you should not reach here")


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
