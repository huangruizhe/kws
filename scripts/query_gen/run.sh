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

    # You'd better use as large corpus as possible.
    # This can come from multiple transcript files

    # This is the trascript file in the kaldi asr directory
    text=()
    # text+=("/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train/text")
    # text+=("/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train_dev/text")
    text+=("/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/text")
    # text+=("/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_eval/text")
    workdir="workdir"
    order=2; freq_thres=1
    # order=3; freq_thres=2

    mkdir -p $workdir

    # Add fisher text (optional)
    # fisher_text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/lm/fisher/text1.gz"
    # # zcat $fisher_text | sed 's/^/uid /' > $workdir/fisher_text.txt
    # zcat $fisher_text | awk '{print "line-"FNR" "$0}' > $workdir/fisher_text.txt
    # text+=("$workdir/fisher_text.txt")

    wc $(printf " %s" "${text[@]}")

    inputfiles=$(printf " -i %s " "${text[@]}")
    python scripts/query_gen/get_collocation.py \
        $inputfiles \
        -w $workdir \
        -n $order -f ${freq_thres}

    log "Done. Please check the output file above. You can make edits in it mannualy if needed."

    head -647 $workdir/lemma_candidates.2.thres1.txt >> $workdir/lemma_candidates.std2006_dev.2.thres1.txt
fi


if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    log "Stage 1: TF-IDF-based unigram mining (actually, lemmas) of 1-ngrams"

    # Choose one of the following:
    # This is the trascript file in the kaldi asr directory
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train/text"
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train_dev/text"
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/text"
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_eval/text"
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt"
    workdir="workdir"

    mkdir -p $workdir

    python scripts/query_gen/get_collocation.py \
        -i $text \
        -w $workdir \
        -n 1

    log "Done. Please check the output file above. You can mannually take top-k unigrams of the file."
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    log "Stage 2: Generate keyword queries for ${order}-ngrams"

    workdir="workdir"

    # std206_dev
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/text"
    dict="$workdir/lemma_candidates.std2006_dev.2.thres1.txt"
    suffix="std2006_dev"
    # std206_eval
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_eval/text"
    dict=
    suffix=""

    order=2

    python scripts/query_gen/get_queries.py \
        -i $text \
        -d $dict \
        -w $workdir \
        -n $order \
        -s $suffix
    
    # merge queries of different orders
fi 

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    log "Stage 3: Adding zero-occurence keywords"

fi 