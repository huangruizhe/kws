import enum
import logging
import argparse
import sys
from typing import NamedTuple


logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--per_category_score', type=str, default=None, help='')
    parser.add_argument('--keywords', type=str, default=None, help='')

    opts = parser.parse_args()
    return opts

def read_keywords(filename):
    id2keywords = dict()
    keywords2id = dict()
    with open(filename, 'r') as fin:
        for line in fin:
            fields = line.strip().split(maxsplit=1)
            kwid = fields[0]
            kw = fields[1]
            id2keywords[kwid] = kw
            keywords2id[kw] = kwid
    logging.info("len(id2keywords)=%d" % len(id2keywords))
    return id2keywords, keywords2id

class KWSTAT(NamedTuple):
    n_kw: int = 0
    n_targ: int = 0
    n_ntarg: int = 0
    n_sys: int = 0
    n_corrDet: int = 0
    n_corrNDet: int = 0
    n_fa: int = 0
    n_miss: int = 0
    atwv: float = 0
    mtwv: float = 0
    otwv: float = 0
    stwv: float = 0
    pfa: float = 0
    mpfa: float = 0
    opfa: float = 0
    pmiss: float = 0
    mpmiss: float = 0
    opmiss: float = 0
    thr: float = 0
    mthr: float = 0
    othr: str = None

def read_per_category_score(filename, keywords):
    kw2stat = dict()
    lines = []
    with open(filename, 'r') as fin:
        lines = fin.readlines()
    lines = lines[3:]
    for line in lines:
        fields = line.strip().split()
        kwid = fields[0]
        if kwid not in keywords:
            continue
        
        n_kw = int(fields[1])
        n_targ = int(fields[2])
        n_ntarg = int(fields[3])
        n_sys = int(fields[4])
        n_corrDet = int(fields[5])
        n_corrNDet = int(fields[6])
        n_fa = int(fields[7])
        n_miss = int(fields[8])
        atwv = float(fields[9])
        mtwv = float(fields[10])
        otwv = float(fields[11])
        stwv = float(fields[12])
        pfa = float(fields[13])
        mpfa = float(fields[14])
        opfa = float(fields[15])
        pmiss = float(fields[16])
        mpmiss = float(fields[17])
        opmiss = float(fields[18])
        thr = float(fields[19])
        mthr = float(fields[20])
        othr = str(fields[21])

        kw2stat[kwid] = KWSTAT(
            n_kw = n_kw,
            n_targ = n_targ,
            n_ntarg = n_ntarg,
            n_sys = n_sys,
            n_corrDet = n_corrDet,
            n_corrNDet = n_corrNDet,
            n_fa = n_fa,
            n_miss = n_miss,
            atwv = atwv,
            mtwv = mtwv,
            otwv = otwv,
            stwv = stwv,
            pfa = pfa,
            mpfa = mpfa,
            opfa = opfa,
            pmiss = pmiss,
            mpmiss = mpmiss,
            opmiss = opmiss,
            thr = thr,
            mthr = mthr,
            othr = othr,
        )
    logging.info("len(kw2stat)=%d" % len(kw2stat))
    return kw2stat

def find_ngrams(input_list, n):
    # https://stackoverflow.com/questions/13423919/computing-n-grams-using-python
    return zip(*[input_list[i:] for i in range(n)])

def main(opts):
    id2keywords, keywords2id = read_keywords(opts.keywords)
    per_category_score = read_per_category_score(opts.per_category_score, id2keywords)

    remove_ids = set()
    for kwid, kw in id2keywords.items():
        if len(kw.split()) == 1:
            continue
        
        stat = per_category_score.get(kwid)
        if stat is None:
            remove_ids.add(kwid)
            continue

        my_ngrams = []
        for i in range(1, len(kw.split())):
            my_ngrams.extend(list(find_ngrams(kw.split(), i)))

        for ng in my_ngrams:
            ng_kw = " ".join(ng)
            if ng_kw not in keywords2id:
                continue
            ng_kwid = keywords2id.get(ng_kw)
            ng_stat = per_category_score.get(ng_kwid)
            if ng_kwid is None or ng_stat is None:
                remove_ids.add(ng_kwid)
                continue

            if stat.n_targ == 0 and stat.n_targ == ng_stat.n_targ:  # distractors, we will keep the shorter phrase
                remove_ids.add(kwid)
            elif ng_stat.n_targ <= stat.n_targ:  # in this case, we will only keep the longer keyphrase
                remove_ids.add(ng_kwid)


    # removed_stwv = [per_category_score[kwid].stwv for kwid in remove_ids if kwid in per_category_score and per_category_score[kwid].n_targ > 0]
    # logging.info(f"Removed STWV = {sum(removed_stwv)/len(removed_stwv)}")

    logging.info(f"There are {len(remove_ids)}/{len(id2keywords)} keywords to remove.")
    for kwid in remove_ids:
        print(kwid)
            

if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
