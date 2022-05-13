import enum
import logging
import argparse
from pathlib import Path
import glob


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--tokens', type=str, default=None, help='')
    parser.add_argument('--best', type=str, default=None, help='')
    parser.add_argument('--words', type=str, default=None, help='')
    parser.add_argument('--k2-ali-files', type=str, help='')
    parser.add_argument('--per_frame_time', type=float, default=0.064, help='')
    parser.add_argument('--shift_nframes', type=float, default=0, help='')

    opts = parser.parse_args()
    return opts


def read_words(filename):
    word2id = dict()
    # id2word = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            word = fields[0]
            wid = int(fields[1])
            word2id[word] = wid
            # id2word[wid] = word
    logging.info("len(word2id)=%d" % len(word2id))
    return word2id


def read_1best(filename):
    best_hyp = dict()  # uid -> word seq
    for f in glob.glob(filename):
        with open(f, 'r') as fin:
            for line in fin:
                fields = line.strip().split(maxsplit=1)
                uid = fields[0]
                if len(fields) == 1:
                    best_hyp[uid] = ""
                else:
                    hyp = fields[1]
                    best_hyp[uid] = hyp
    logging.info("len(best_hyp)=%d" % len(best_hyp))
    return best_hyp


def read_tokens(filename):
    id2token = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            token = fields[0]
            tid = int(fields[1])
            id2token[tid] = token
    logging.info("len(id2token)=%d" % len(id2token))
    return id2token


def change_frame_rate(line, from_frame_time, to_frame_time):
    rs = list()
    rate = from_frame_time / to_frame_time
    for w, t in line:
        rs.append((w, round(t * rate)))
    return rs


def pad_and_shift(line, nframes):
    # shift left: nframes < 0
    # shift right: nframes > 0

    if nframes < 0:
        w0, t0 = line[0]
        line[0] = (w0, max(1, t0 + nframes))
        w1, t1 = line[-1]
        line[-1] = (w1, t1 + (t0 - line[0][1]))
    else:
        w1, t1 = line[-1]
        line[-1] = (w1, max(1, t1 - nframes))
        w0, t0 = line[0]
        line[0] = (w0, t0 + (t1 - line[-1][1]))
    return line


def change_words_id(line, word2id_from, word2id_to):
    rs = list()
    for w, t in line:
        rs.append((w, round(t * rate)))
    return rs


def word2ali1(line, per_frame_time):
    # This function provides the center (or start) and the duration for each word in the word-level CTC sequence

    # Strategy 1:
    # Start/Midpoint: Each word starts at where the symbol appears in the sequence
    # Duration: min(max_word_len, #frames between two words)

    # per_frame_time = 0.016 * 4
    max_word_len = int(0.64 / per_frame_time)  # 0.6 second

    rs = list()
    word_start = 0
    for i, tk in enumerate(line):
        if tk > 0:
            if i - word_start > 0:   # TODO: what if the line starts with non-zero?
                if i - word_start > max_word_len:
                    rs.append((line[word_start], max_word_len))
                    rs.append((0, i - word_start - max_word_len))
                else:
                    rs.append((line[word_start], i - word_start))
                word_start = i
    
    i = len(line)
    if i - word_start > 0:
        if i - word_start > max_word_len:
            rs.append((line[word_start], max_word_len))
            rs.append((0, i - word_start - max_word_len))
        else:
            rs.append((line[word_start], i - word_start))

    assert len(line) == sum([i for _, i in rs]), f"{len(line)} != {sum([i for _, i in rs])}"
    return rs


def process(opts, filename, word2id, best_hyp, id2token):

    process_cnt = 0
    unkid = word2id["<unk>"]

    def token2word(line):
        rs = list()
        word_seq = ""
        cur_word = ""
        word_position = -1
        for i, tk in enumerate(line):
            if tk == 0:
                rs.append(0)
            elif tk == -1:
                if len(cur_word) > 0:
                    rs[word_position] = word2id.get(cur_word, unkid)
                    word_seq += cur_word
                rs.append(0)
            elif id2token[tk].startswith("▁"):  # Be careful! This is not an underline
                if len(cur_word) > 0:
                    rs[word_position] = word2id.get(cur_word, unkid)
                    word_seq += cur_word + ' '
                word_position = i
                cur_word = id2token[tk][1:]
                rs.append(0)
            elif tk > 0:
                cur_word += id2token[tk]
                rs.append(0)
            else:
                logging.error("Cannot reach here")
        return rs, word_seq

    shift_nframes = opts.shift_nframes

    with open(filename, "r") as fin:
        for line in fin:
            line = line.strip()
            if len(line) == 0:
                continue

            fields = line.split(maxsplit=1)
            uid = fields[0]
            if len(fields) == 1:
                logging.info("Empty utterance:" + "%s\t%s" % (uid, ""))
                print("%s\t%s" % (uid, ""))
                continue
            
            k2ali = [int(i) for i in fields[1].split()]

            word_hyp = best_hyp[uid]
            k2ali_word, word_seq = token2word(k2ali)
            assert word_seq == word_hyp, f"hyp: {word_hyp} ---- my decoding: {word_seq}"
            # print(''.join(["%d:%05d " % (i, tk) for i, tk in enumerate(k2ali)]))
            # print(''.join(["%d:%05d " % (i, tk) for i, tk in enumerate(k2ali_word)]))
            # print(uid, word_seq)
            # print()

            rs = word2ali1(k2ali_word, opts.per_frame_time)
            rs = change_frame_rate(rs, opts.per_frame_time, 0.01)
            rs = pad_and_shift(rs, shift_nframes)
            print("%s\t%s" % (uid, " ; ".join(map(lambda x : "%d %d" % x, rs))))
            process_cnt += 1
    
    return process_cnt


def main(opts):
    word2id = read_words(opts.words)
    best_hyp = read_1best(opts.best.replace("\\", ""))
    id2token = read_tokens(opts.tokens)

    cnt = 0
    for f in glob.glob(opts.k2_ali_files.replace("\\", "")):
        assert f.endswith("best_path_aux_labels"), f"Filename: {f}"
        cnt += process(opts, f, word2id, best_hyp, id2token)
    
    logging.info("Done %d utterances." % cnt)


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)


# kaldi's 1st best alignment
# /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/tri3_ali_1best_kaldi_eval2000/1best.ali.txt
# kaldi's gt alignment
# /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/tri3_ali_gt_eval2000/1best.ali.txt
# espnet+k2's 1st best alignment
# exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_1_bw-0.2_lmwt0.2/eval2000//1best.k2.ali.txt

# ESPNET's vocab
# --words "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large/lang/words.txt" \

# Kaldi's vocab
# script="/export/fs04/a12/rhuang/kws/kws/local/k2ali2ali.py"
# test_set=eval2000
# test_set=std2006_dev
# test_set=callhome_dev
# decode=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_1_bw-0.2_lmwt0.2/${test_set}/
# python $script \
#     --tokens "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large/lang/tokens.txt" \
#     --words "/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt" \
#     --best "${decode}/logdir/output.\\*/1best_recog/text" \
#     --k2-ali-files "${decode}/logdir/output.\\*/1best_recog/best_path_aux_labels" \
#     > ${decode}/1best.k2.ali.txt

