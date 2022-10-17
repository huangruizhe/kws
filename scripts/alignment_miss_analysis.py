# !/usr/bin/env python3

from collections import defaultdict

import argparse
import sys


def get_args():
    parser = argparse.ArgumentParser(description="""abcd""")

    # parser.add_argument('trans_book', type=str, help="""Map between words that
    #     is transliterated to its orignal form.""")
    parser.add_argument('--keywords', type=str, default=None, help="""keywords.txt""")
    parser.add_argument('--words', type=str, default=None, help="""words.txt""")
    parser.add_argument('--utt_map', type=str, default=None, help="""utt_map""")
    parser.add_argument('--results', type=str, default=None, help="""results""")
    parser.add_argument('--alignment', type=str, default=None, help="""alignment.csv""")
    args = parser.parse_args()

    return args


def parse_ll(ll, utt_map, keywords_map):
    language=ll[0]
    utt=utt_map[ll[1]] if utt_map is not None else ll[1]
    channel=ll[2]
    termid=ll[3]
    term=keywords_map[ll[4]] if keywords_map is not None else ll[4]
    ref_bt=ll[5]
    ref_et=ll[6]
    sys_bt=ll[7]
    sys_et=ll[8]
    sys_score=ll[9]
    sys_decision=ll[10]
    alignment=ll[11]
    recording_id = "_".join(utt.split("_")[:-1])
    return {
        "language": language,
        "utt": utt,
        "channel": channel,
        "termid": termid,
        "term": term,
        "ref_bt": ref_bt,
        "ref_et": ref_et,
        "sys_bt": sys_bt,
        "sys_et": sys_et,
        "sys_score": sys_score,
        "sys_decision": sys_decision,
        "alignment": alignment,
        "recording_id": recording_id,
    }


def read_alignment(args):
    keywords_map = dict()
    # keywords_path = "/Users/huangruizhe/Codes/siamese/data/train_safet_sp/keywords.txt"
    # keywords_path = siamese_root_dir + "/data/train_safet_sp/keywords.txt"
    keywords_path = args.keywords
    if keywords_path is not None:
        with open(keywords_path, 'r', encoding="utf-8") as fin:
            for l in fin:
                ll = l.strip().split(maxsplit=1)
                keywords_map[ll[0]] = ll[1]
    # print("len(keywords_map)=%d" % len(keywords_map))

    # filename = "/Users/huangruizhe/Codes/siamese/data/train_safet_sp/words.txt"
    # filename = siamese_root_dir + "/data/train_safet_sp/words.txt"
    filename = args.words
    words2id = dict()
    if filename is not None:
        with open(filename, 'r', encoding="utf-8") as fin:
            for l in fin:
                ll = l.strip().split(maxsplit=2)
                words2id[ll[0]] = int(ll[1])
    # print("len(words)=%d" % len(words2id))

    utt_map = dict()
    # utt_map_path = "/Users/huangruizhe/Codes/siamese/data/train_safet_sp/utt.map"
    # utt_map_path = siamese_root_dir + "/data/train_safet_sp/utt.map"
    utt_map_path = args.utt_map
    if utt_map_path is not None:
        with open(utt_map_path, 'r', encoding="utf-8") as fin:
            for l in fin:
                ll = l.strip().split()
                utt_map[ll[1]] = ll[0]
    # print("len(utt_map)=%d" % len(utt_map))

    expid = str(89)

    results = list()
    # results_path = "/export/fs04/a12/rhuang/siamese/siamese/results/20210416/%s/results" % expid
    results_path = args.results
    if results_path is not None:
        with open(results_path, 'r', encoding="utf-8") as fin:
            for l in fin:
                ll = l.strip().split()
                results.append(ll[-1])

    # alignment = "/Users/huangruizhe/Codes/siamese/data/alignment_0.7733.csv"
    # alignment = siamese_root_dir + "/data/alignment_0.7733.csv"
    # alignment = "/Users/huangruizhe/Downloads/dev/alignment.8539.csv"
    # alignment = "/export/fs04/a12/rhuang/siamese/siamese/results/20210416/87/alignment.csv"
    # alignment = "/export/fs04/a12/rhuang/siamese/siamese/results/20210416/89/alignment.csv"
    # alignment = "/export/fs04/a12/rhuang/siamese/siamese/results/20210416/orignal/alignment.csv"
    # alignment = "/export/fs04/a12/rhuang/siamese/siamese/results/20210416/" + expid + "/alignment.csv"
    alignment = args.alignment

    kw2hits = defaultdict(list)
    with open(alignment, 'r', encoding="utf-8") as fin:
        line_count = 0
        for l in fin:
            if line_count < 1:  # skip the header
                line_count += 1
                # print(l.strip())
                continue
            else:
                ll = l.strip().split(sep=",")
                hit = parse_ll(ll, utt_map, keywords_map)
                kw2hits[hit["term"]].append(hit)

    lattice_miss_count = 0
    lattice_miss_but_in_cache_count = 0
    target_kws = set()
    for kw, hits in kw2hits.items():
        hits_subset = [(j, hit) for j, hit in enumerate(hits) if hit["sys_bt"] != ""]
        for i, hit1 in enumerate(hits):
            if hit1["alignment"] != "MISS":
                continue
            
            if hit1["sys_bt"] != "":
                continue
            
            lattice_miss_count += 1
            
            for j, hit2 in hits_subset:
                if j == i:  # the same hit
                    continue
                if hit2["recording_id"] == hit1["recording_id"]:
                # if hit2["recording_id"] == hit1["recording_id"] and hit2["alignment"] == "CORR":
                    lattice_miss_but_in_cache_count += 1
                    target_kws.add((kw, hit1["recording_id"]))
                    break
        
    print(f"lattice_miss_count={lattice_miss_count}")
    print(f"lattice_miss_but_in_cache_count={lattice_miss_but_in_cache_count}")
    
    for i in range(max([len(kw.split()) for kw, rec in target_kws])):
        ngrams = [(kw, rec) for kw, rec in target_kws if len(kw.split()) == i+1]
        print(f"{i+1}-gram (count={len(ngrams)}): {ngrams} \n")

def main():
    args = get_args()
    read_alignment(args)


if __name__ == "__main__":
    main()


