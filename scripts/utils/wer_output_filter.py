#!/usr/bin/env python3

import re
import sys
import argparse


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


def filter(text):
    # check letter case
    if text.isupper():
        letter_case = "upper"
    elif text.islower():
        letter_case = "lower"
    else:
        letter_case = "mix"

    text = text.lower()

    # TODO:
    # callhome_dev: en_0638_0B_00002 i already got another [yelling] [[there are background noises throughout this conversation but they in no way interfere with the speakers]] apartment

    # rewrite words to standardized form with the dict
    # (1) words starting with & are entity names
    text = re.sub('[.,!?:;&%#\*/]+', ' ', text)
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


def parse_opts():
    parser = argparse.ArgumentParser(
        description='Get collocations',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--no-uid', action='store_true', default=False)

    opts = parser.parse_args()
    return opts


def main(opts):
    for line in sys.stdin:

        line = line.strip()
        if len(line) == 0:
            continue
        
        if not opts.no_uid:
            try:
                utt, text = line.split(None, 1)
            except:
                print(line)
                continue

            text = filter(text)
            print("{} {}".format(utt, text))
        else:
            text = filter(line)
            print(text)

if __name__ == '__main__':
    opts = parse_opts()
    main(opts)


# grep "<" exp/chain/tdnn7r_sp/decode_eval2000_sw1_fsh_fg/score_sclite/score_10_0.0/eval2000_hires.ctm.filt | \
#   cut -d" " -f5- sth | sort -u
#
# <ALT>
# <ALT_BEGIN>
# <ALT_END>

# test_set=std2006_dev
# test_set=callhome_dev
# ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${test_set}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
# data=data/${test_set}/
# decode=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_1_bw-0.2_lmwt0.2/${test_set}/
# hyp=$decode/text

# bash local/score_kaldi_light.sh $ref $hyp $data $decode
# expecting 15.15% for std2006_dev