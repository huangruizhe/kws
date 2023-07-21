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
    log "Stage 0: PMI-based Phrase mining (actually, lemmas) of ${order}-ngrams with frequency threshold=${freq_thres}"

    cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
    . ./path.sh
    . ./cmd.sh

    cd /export/fs04/a12/rhuang/kws/kws-release
    ln -s /export/fs04/a12/rhuang/kaldi_latest/kaldi/egs/wsj/s5/utils .

    # TODO: shall we use a large corpus coming from multiple transcript files?

    data=

    # This is the trascript file in the kaldi asr directory
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/${data}/text"
    workdir="workdir"
    order=2; freq_thres=1
    # order=3; freq_thres=2

    mkdir -p $workdir

    cat $text | python scripts/utils/wer_output_filter.py > $workdir/${data}.text
    wc $text $workdir/${data}.text
    
    python scripts/query_gen/get_collocation.py \
        -i $workdir/${data}.text \
        -w $workdir \
        -n $order \
        -d $data \
        -f ${freq_thres}

    log "Done. Please check the output file above. You can make edits in it mannualy if needed."

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

    # Choose one of the following:
    # This is the trascript file in the kaldi asr directory
    # text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train/text"
    # text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train_dev/text"
    # text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/text"
    # text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_eval/text"
    # text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt"
    text=$workdir/${data}.text
    workdir="workdir"

    mkdir -p $workdir

    python scripts/query_gen/get_collocation.py \
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

    text=$workdir/${data}.text
    workdir="workdir"

    # Assuming there is a list of candidate words
    # Here we just take the NIST2006KWS keyword list
    cat /export/fs04/a12/rhuang/kws/kws/data0/std2006_dev/kws/keywords.std2006_dev.txt \
        /export/fs04/a12/rhuang/kws/kws/data0/std2006_eval/kws/keywords.std2006_eval.txt \
        > $workdir/keywords.NIST2006KWS.txt

    python scripts/query_gen/check_occurence.py \
        --text $text \
        --wordlist $workdir/keywords.NIST2006KWS.txt \
        --maxorder 3 \
        > $workdir/keywords.0.$data.txt
    wc -l $workdir/keywords.0.$data.txt
fi 

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    log "Stage 2: Generate keyword queries for ${order}-ngrams"

    data=
    workdir="workdir"

    # You may need to set the following mannually
    text=$workdir/${data}.text
    order=1
    dict="$workdir/lemma_candidates.$data.$order.txt.0.5"
    order=2
    dict="$workdir/lemma_candidates.$data.$order.thres1.txt.*.*"
    order=3
    dict="$workdir/lemma_candidates.$data.$order.thres2.txt"

    python scripts/query_gen/get_queries.py \
        -i $text \
        -d $dict \
        -w $workdir \
        -n $order \
        -s $data
    
    # merge queries of different orders
    # then, sort by the number of columns
    # then print the kw ids
    ls -1 $workdir/keywords.*.$data.txt
    cat $workdir/keywords.*.$data.txt | awk 'NF{NF-=1};1' |\
        awk '{ print NF, $0 }' | sort -n | cut -d' ' -f2- |\
        awk '{ printf("KW-%05d\t%s\n", NR, $0) }' > $workdir/keywords.$data.txt
    wc $workdir/keywords.$data.txt
fi 