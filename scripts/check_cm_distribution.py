import logging
import argparse
import re
import numpy as np
from scipy.special import logsumexp

# python -m wer_output_filter check_cm_distribution.py --per_utt a --one_best_text bb --one_best_score cc
# from .wer_output_filter import filter_dict

filter_dict = dict()

filter_dict["uh"] = "(%hesitation)"
filter_dict["um"] = "(%hesitation)"
filter_dict["hm"] = "(%hesitation)"
filter_dict["huh"] = "(%hesitation)"
filter_dict["ah"] = "(%hesitation)"

filter_dict["uh-huh"] = "uhhuh"
filter_dict["um-hum"] = "uhhuh"
filter_dict["mhm"] = "uhhuh"
filter_dict["mmhm"] = "uhhuh"
filter_dict["mm-hm"] = "uhhuh"
filter_dict["mm-huh"] = "uhhuh"
filter_dict["huh-uh"] = "uhhuh"

filter_dict["it's"] = "it is"
filter_dict["i'm"] = "i am"
filter_dict["he's"] = "he is"
filter_dict["she's"] = "she is"
filter_dict["you're"] = "you are"
filter_dict["we're"] = "we are"
filter_dict["they're"] = "they are"
filter_dict["that's"] = "that is"
filter_dict["what's"] = "what is"
filter_dict["who's"] = "who is"
filter_dict["there's"] = "there is"
filter_dict["isn't"] = "is not"
filter_dict["aren't"] = "are not"
filter_dict["don't"] = "do not"
filter_dict["can't"] = "cannot"
filter_dict["wasn't"] = "was not"
filter_dict["won't"] = "will not"
filter_dict["didn't"] = "did not"
filter_dict["doesn't"] = "does not"
filter_dict["haven't"] = "have not"
filter_dict["hadn't"] = "had not"
filter_dict["wouldn't"] = "would not"
filter_dict["couldn't"] = "could not"
filter_dict["i've"] = "i have"
filter_dict["you've"] = "you have"
filter_dict["we've"] = "we have"
filter_dict["they've"] = "they have"
filter_dict["i'll"] = "i will"
filter_dict["it'll"] = "it will"
filter_dict["you'll"] = "you will"
filter_dict["he'll"] = "he will"
filter_dict["she'll"] = "she will"
filter_dict["we'll"] = "we will"
filter_dict["that'll"] = "that will"
filter_dict["i'd"] = "i would"
filter_dict["gonna"] = "going to"
filter_dict["wanna"] = "want to"
filter_dict["let's"] = "let us"


def wer_output_filter(text):
    # check letter case
    if text.isupper():
        letter_case = "upper"
    elif text.islower():
        letter_case = "lower"
    else:
        letter_case = "mix"

    text = text.lower()

    # rewrite words to standardized form with the dict
    # (1) words starting with & are entity names
    text = re.sub('[.,!?:&]', ' ', text)
    text = " ".join([filter_dict.get(word, word) for word in text.strip().split()])

    # words beginning or ending with { or }
    text = re.sub('{[^\s]*?}', ' ', text)
    text = re.sub(r'{[^\s]*[\b\s]?', '', text)
    text = re.sub(r'[\b\s]?[^\s]*}', '', text)
    
    # words beginning or ending with [ or ]
    text = re.sub(r'\[\[[^\s]*?\]\]', ' ', text)
    text = re.sub(r'\[[^\s]*?\]', ' ', text)
    text = re.sub(r'\[[^\s]*[\b\s]?', '', text)  # https://stackoverflow.com/questions/525635/regular-expression-match-start-or-whitespace
    text = re.sub(r'[\b\s]?[^\s]*\]', '', text)  # \b is word boundary

    # words beginning or ending with ( or )
    text = re.sub(r'\(\([^\s]*?\)\)', ' ', text)
    text = re.sub(r'\([^\s]*?\)', ' ', text)   # optionally match
    text = re.sub(r'\([^\s]*[\b\s]?', '', text)
    text = re.sub(r'[\b\s]?[^\s]*\)', '', text)

    # words beginning or ending with < or >
    text = re.sub('<[^\s]*?>', ' ', text)
    text = re.sub(r'<[^\s]*[\b\s]?', '', text)
    text = re.sub(r'[\b\s]?[^\s]*>', '', text)

    text = re.sub('%[a-z]+', ' ', text)
    text = re.sub(r'/', ' ', text)
    text = re.sub('_', ' ', text)
    text = re.sub('([^\s])-([^\s])', r'\1 \2', text)  # hyphen between words are replaced with space
    text = re.sub(r'\*', '', text)
    text = re.sub('\+', ' ', text)
    text = re.sub('<', ' ', text)
    text = re.sub('>', ' ', text)
    text = re.sub('#', ' ', text)

    # (1) words starting or ending with - is optionally deletable -- so delete them all here
    text = re.sub(' [-][^\s]*?(?=\s)', ' ', text)  # look ahead mechanism for overlapping patterns
    text = re.sub(' [-][^\s]*?$', '', text)
    text = re.sub('^[-][^\s]*?(?=\s)', '', text)
    text = re.sub('^[-][^\s]*?$', '', text)
    text = re.sub(' [^\s]*?-(?=\s)', ' ', text)
    text = re.sub(' [^\s]*?-$', '', text)
    text = re.sub('^[^\s]*?-(?=\s)', '', text)
    text = re.sub('^[^\s]*?-$', '', text)
    
    text = re.sub(' -- ', ' ', text)
    text = re.sub(' --$', '', text)
    text = re.sub('^-- ', '', text)
    text = re.sub('\s+', ' ', text)
    text = re.sub('\s+$', '', text)

    text = text.strip()

    # Preserver letter case (not 100% though)
    if letter_case == "upper":
        text = text.upper()
    elif letter_case == "lower":
        text = text.lower()
        
    return text.strip()


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--per_utt', type=str, default=None, help='')
    parser.add_argument('--one_best_text', type=str, help='')
    parser.add_argument('--one_best_score', type=str, help='')
    parser.add_argument('--cm_alignment', type=str, help='')
    parser.add_argument('--scale', type=float, default=1.0, help='')
    parser.add_argument('--text_start_col', type=int, default=2, help='')

    opts = parser.parse_args()
    return opts


def parse_per_utt(filename):
    with open(filename, "r") as fin:
        lines = fin.readlines()
    
    per_utt = dict()
    for i in np.arange(0, len(lines), 4, dtype=int):
        ref = lines[i]
        hyp = lines[i + 1]
        op = lines[i + 2]
        csid = lines[i + 3]

        hyp = hyp.split()
        uid = hyp[0]
        hyp = hyp[2:]
        op = op.split()[2:]

        assert len(hyp) == len(op)

        rs = [(w, o) for w, o in zip(hyp, op) if o != "D"]
        per_utt[uid] = rs
    
    logging.info(f"len(per_utt)={len(per_utt)}")
    return per_utt


def read_one_best(file_text, file_score, scale, text_start_col):
    one_best = dict()
    uid_uttscore = dict()
    uttscores = list()
    uid = None
    with open(file_text, "r") as fin_text, open(file_score, "r") as fin_score:
        for line_text, line_score in zip(fin_text, fin_score):
            line_text = line_text.strip()
            line_score = line_score.strip()

            if len(line_text) == 0 or len(line_score) == 0:
                continue
            
            line_text = line_text.split()
            line_score = line_score.split()
            assert line_text[0] == line_score[0]
            assert len(line_text[text_start_col:]) == len(line_score[1:]) or line_text[text_start_col:][-1] == "⁇"

            if line_text[0] != uid:  # new utterance
                if uid is not None:
                    scores = np.asarray(uttscores) * scale
                    logsum = logsumexp(scores)
                    scores -= logsum
                    uid_uttscore[uid] = scores[0]
                    uttscores = list()
                    
                uid = line_text[0]
                rs = [(w, float(s)) for w, s in zip(line_text[text_start_col:], line_score[1:])]
                one_best[uid] = rs
                uttscores.append(float(line_text[1] if text_start_col == 2 else 1.0))
            else:
                uttscores.append(float(line_text[1] if text_start_col == 2 else 1.0))
        
        # last utterance
        if uid is not None:
            scores = np.asarray(uttscores) * scale
            logsum = logsumexp(scores)
            scores -= logsum
            uid_uttscore[uid] = scores[0]      

    logging.info(f"len(one_best)={len(one_best)}")
    logging.info(f"len(uid_uttscore)={len(uid_uttscore)}")
    return one_best, uid_uttscore


def do_alignment(per_utt, one_best, uid_uttscore):
    # Due to wer_output_filter, the words in "per_utt" and "one_best" may not match exactly
    alignment = dict()
    for uid, best in one_best.items():
        utt_op = per_utt[uid]

        # The word sequence in "best" will go through wer_output_filter to become the word seq in utt_op
        align = list()
        i_utt = 0
        i_best = 0
        while i_best < len(best):
            word = best[i_best][0]
            word_filtered = wer_output_filter(word)
            word_filtered = word_filtered.strip()
            
            if len(word_filtered) == 0:  # We don't consider the words that's been filtered out, like [noise]
                i_best += 1
                continue

            if i_utt >= len(utt_op):
                logging.info(f"[warning] break for {uid}")
                break

            word_filtered = word_filtered.split()  # we will only consider the first word, as it corresponds to one confidence measure
            assert word_filtered[0] == utt_op[i_utt][0], f"{word_filtered[0]} vs. {utt_op[i_utt][0]} in {best} {utt_op}"
            # align.append((word_filtered[0], best[i_best][1], uid_uttscore[uid], utt_op[i_utt][1]))  # (word, word_cm, utt_posterior, op)
            align.append((word, best[i_best][1], uid_uttscore[uid], utt_op[i_utt][1]))  # (word, word_cm, utt_posterior, op)
            i_best += 1
            i_utt += len(word_filtered)
        
        assert i_utt == len(utt_op) or utt_op[-1][0] == "⁇", f"{i_utt} != {len(utt_op)} in {best} {utt_op}"
        alignment[uid] = align
    logging.info(f"len(alignment)={len(alignment)}")
    return alignment


def do_alignment2(per_utt, one_best, uid_uttscore):  # This version will keep the words filtered out and give them a None tag
    # Due to wer_output_filter, the words in "per_utt" and "one_best" may not match exactly
    alignment = dict()
    for uid, best in one_best.items():
        utt_op = per_utt[uid]

        # The word sequence in "best" will go through wer_output_filter to become the word seq in utt_op
        align = list()
        i_utt = 0
        i_best = 0
        while i_best < len(best):
            word = best[i_best][0]
            word_filtered = wer_output_filter(word)
            # word_filtered = word
            word_filtered = word_filtered.strip()
            
            if len(word_filtered) == 0:  # We don't consider the words that's been filtered out, like [noise]
                align.append((word, best[i_best][1], uid_uttscore[uid], 'N'))  # (word, word_cm, utt_posterior, op)
                i_best += 1
                continue

            if i_utt >= len(utt_op):
                logging.info(f"[warning] break for {uid}")
                break

            word_filtered = word_filtered.split()  # we will only consider the first word, as it corresponds to one confidence measure
            assert word_filtered[0] == utt_op[i_utt][0], f"{word_filtered[0]} vs. {utt_op[i_utt][0]} in {best} {utt_op}"
            # align.append((word_filtered[0], best[i_best][1], uid_uttscore[uid], utt_op[i_utt][1]))  # (word, word_cm, utt_posterior, op)
            align.append((word, best[i_best][1], uid_uttscore[uid], utt_op[i_utt][1]))  # (word, word_cm, utt_posterior, op)
            i_best += 1
            i_utt += len(word_filtered)
        
        assert i_utt == len(utt_op) or utt_op[-1][0] == "⁇", f"{i_utt} != {len(utt_op)} in {best} {utt_op}"
        alignment[uid] = align
    logging.info(f"len(alignment)={len(alignment)}")
    return alignment


def main(opts):
    per_utt = parse_per_utt(opts.per_utt)
    one_best, uid_uttscore = read_one_best(opts.one_best_text, opts.one_best_score, opts.scale, opts.text_start_col)
    # alignment = do_alignment(per_utt, one_best, uid_uttscore)
    alignment = do_alignment2(per_utt, one_best, uid_uttscore)  # keep those filtered words
    
    with open(opts.cm_alignment, "w") as fout:
        for uid, align in alignment.items():
            align_str = " ".join(map(lambda x: f"({x[0]} {x[1]:.4f} {x[2]:.4f} {x[3]}),", align))
            output_str = f"{uid} {align_str}"
            print(output_str, file=fout)


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)

# --per_utt /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_normal_token_scores/std2006_dev/scoring_kaldi/wer_details/per_utt
# --one_best_text /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices/std2006_dev_100_tokenscores/temp/1/nbest.txt
# --one_best_score /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices/std2006_dev_100_tokenscores/temp/1/nbest_w_scores.txt
# --cm_alignment /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices/std2006_dev_100_tokenscores/temp/1/cm_alignment.txt
