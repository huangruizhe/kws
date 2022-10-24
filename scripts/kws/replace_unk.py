import enum
import logging
import argparse
import sys


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--text', type=str, default=None, help='')
    parser.add_argument('--words', type=str, default=None, help='')
    parser.add_argument('--unk', type=str, default="<unk>", help='')

    opts = parser.parse_args()
    return opts


def read_text(filename):
    utt2text = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            uid = fields[0]
            sent = fields[1:]
            utt2text[uid] = sent
    logging.info("len(utt2text)=%d" % len(utt2text))
    return utt2text


def read_words(filename):
    id2word = dict()
    word2id = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split()
            word = fields[0]
            wid = int(fields[1])
            id2word[wid] = word
            word2id[word] = wid
    logging.info("len(id2word)=%d" % len(id2word))
    return id2word, word2id
    

def main(opts):
    utt2text = read_text(opts.text)
    id2word, word2id = read_words(opts.words)
    
    for line in sys.stdin:
        fields = line.strip().split(maxsplit = 1)
        uid = fields[0]
        sent = utt2text[uid]

        ali = map(lambda x: x.strip().split(), fields[1].split(";"))
        ali = [(int(x[0]), int(x[1])) for x in ali]
        ali_without_sil = [x for x in ali if x[0] != 0]
        if len(ali) == 0 or len(sent) != len(ali_without_sil):
            logging.error(f"Problem with len(ali_without_sil): {len(sent)}!={len(ali_without_sil)}")
            logging.error(f"{line}")
            logging.error(f"{uid} {' '.join(sent)}")
            exit(1)

        new_ali = ""
        for w_ref, w_ali in zip(sent, ali):
            if w_ref == opts.unk:
                ali_w_id = word2id[w_ref]
            else:
                ali_w_id = w_ali[0]
            new_ali += f" {ali_w_id} {w_ali[1]} ;"
        if new_ali.endswith(";"):
            new_ali = new_ali[:-1]
        
        print(f"{uid} {new_ali}")


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
