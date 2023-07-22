#!/bin/bash
# Copyright (c) 2021-2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

############################################################
# Given some text files,
# we will output a list of keywords that can be used for KWS
#
# This script is designed to run step-by-step, instead of `bash run.sh`
############################################################


# From ESPNet:
# https://github.com/espnet/espnet/blob/master/egs2/TEMPLATE/asr1/asr.sh
# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

log() {
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%dT%H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

stage=
stop_stage=

log "$0 $*"
# Save command line args for logging (they will be lost after utils/parse_options.sh)
# run_args=$(pyscripts/utils/print_args.py $0 "$@")
. utils/parse_options.sh


if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    # Use this corpus for demonstration purpose

    git clone git@github.com:christos-c/bible-corpus.git

    python -c '''
import xml.etree.ElementTree as ET
import glob
files = glob.glob(f"bible-corpus/bibles/*.xml")
for f in files:
  print(f)
  root = ET.fromstring(open(f).read())
  with open(f[:f.rfind(".")] + ".txt", "w", encoding="utf-8") as out:
    for n in root.iter("seg"):
      if n.text is None: continue
      out.write(n.text.strip() + "\n")
'''

    ls bible-corpus/bibles/*.txt 
fi


if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    log "Stage 0: PMI-based Phrase mining (actually, lemmas) of ${order}-ngrams with frequency threshold=${freq_thres}"

    git clone git@github.com:huangruizhe/kws.git
    cd kws

    # TODO: shall we use a large corpus for robust PMI estimation?

    # This is the trascript file in the kaldi asr directory
    text="<path-to-your-corpus>/bible-corpus/bibles/English.txt"
    text="<path-to-your-corpus>/bible-corpus/bibles/Chinese.txt"
    workdir="workdir"
    order=2; freq_thres=1
    # order=3; freq_thres=2

    mkdir -p $workdir

    # You can do some text normalization for your language:
    cat $text | python scripts/utils/wer_output_filter.py --no-uid > $workdir/cleaned.text
    cat $workdir/cleaned.text | python scripts/query_gen_general/get_lemma.py > $workdir/normed.text
    # The line numbers should be the same here:
    wc $text $workdir/cleaned.text $workdir/normed.text
 
    # text_input=$text
    text_input=$workdir/normed.text
    
    python scripts/query_gen_general/get_collocation.py \
        -i $text_input \
        -w $workdir \
        -n $order \
        -f ${freq_thres}

    log "Done. Please check the output file above. You can make edits/filtering in it mannualy if needed."

    # head -647 $workdir/lemma_candidates.2.thres1.txt >> $workdir/lemma_candidates.std2006_dev.2.thres1.txt

    # https://unix.stackexchange.com/questions/188095/remove-lines-where-a-fields-value-is-less-than-or-equal-to-3-sed-or-awk
    awk '( $(NF) > 9.0 ) ' workdir/lemma_candidates.std2006_dev.2.thres1.txt > workdir/lemma_candidates.std2006_dev.2.thres1.txt.9.0
    awk '( $(NF) > 10.0 ) ' workdir/lemma_candidates.std2006_eval.2.thres1.txt > workdir/lemma_candidates.std2006_eval.2.thres1.txt.10.0
    awk '( $(NF) > 10.7 ) ' workdir/lemma_candidates.callhome_dev.2.thres1.txt > workdir/lemma_candidates.callhome_dev.2.thres1.txt.10.7
    awk '( $(NF) > 9.0 ) ' workdir/lemma_candidates.callhome_eval.2.thres1.txt > workdir/lemma_candidates.callhome_eval.2.thres1.txt.9.0
    wc -l $workdir/*
fi


if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    log "Stage 1: TF-IDF-based unigram mining (actually, lemmas) of 1-ngrams"

    # text_input=$text
    text_input=$workdir/normed.text
    workdir="workdir"

    mkdir -p $workdir

    python scripts/query_gen_general/get_collocation.py \
        -i $text \
        -w $workdir \
        -n 1

    log "Done. Please check the output file above. You can mannually take top-k unigrams of the file."

    # get the first half
    file=workdir/lemma_candidates.$data.1.txt
    awk -v totrecs=$(wc -l < $file) ' {if (NR <= totrecs/2) {print $0}}' $file > $file.0.5
    wc -l $file $file.0.5
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    log "Stage 3: Adding zero-occurence keywords"

    text_input=$workdir/normed.text
    workdir="workdir"

    # Assuming there is a list of candidate words
    # Here we just take the NIST2006KWS keyword list
    cat /export/fs04/a12/rhuang/kws/kws/data0/std2006_dev/kws/keywords.std2006_dev.txt \
        /export/fs04/a12/rhuang/kws/kws/data0/std2006_eval/kws/keywords.std2006_eval.txt \
        > $workdir/keywords.NIST2006KWS.txt

    python scripts/query_gen_general/check_occurence.py \
        --text $text \
        --wordlist $workdir/keywords.NIST2006KWS.txt \
        --maxorder 3 \
        > $workdir/keywords.0.$data.txt
    wc -l $workdir/keywords.0.$data.txt
fi 

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    log "Stage 4: Generate keyword queries for ${order}-ngrams: un-normalize, apply heuristics and so on"

    text_input=$workdir/normed.text
    workdir="workdir"
    text_orig=$workdir/cleaned.text

    # You may need to set the following mannually
    order=1
    dict="$workdir/lemma_candidates.$order.txt"
    order=2
    dict="$workdir/lemma_candidates.$order.thres1.txt"
    order=3
    dict="$workdir/lemma_candidates.$order.thres2.txt"

    python scripts/query_gen_general/get_queries.py \
        -i $text_input \
        -r $text_orig \
        -d $dict \
        -w $workdir \
        -n $order 
    # You should get the list of keywords of the specific order now
    
    # merge queries of different orders
    # then, sort by the number of columns
    # then print the kw ids
    ls -1 $workdir/keywords.*.$data.txt
    cat $workdir/keywords.*.$data.txt | awk 'NF{NF-=1};1' |\
        awk '{ print NF, $0 }' | sort -n | cut -d' ' -f2- |\
        awk '{ printf("KW-%05d\t%s\n", NR, $0) }' > $workdir/keywords.$data.txt
    wc $workdir/keywords.$data.txt
fi 