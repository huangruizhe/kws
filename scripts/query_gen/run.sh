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
    text+=("/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train/text")
    text+=("/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train_dev/text")
    text+=("/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/text")
    text+=("/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_eval/text")
    workdir="workdir"
    order=2; freq_thres=2
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
fi


if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    log "Stage 0: TF-IDF-based unigram mining (actually, lemmas) of ${order}-ngrams"

    # This is the trascript file in the kaldi asr directory
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train/text"
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/train_dev/text"
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/text"
    text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_eval/text"
    workdir="workdir"

    mkdir -p $workdir

    python scripts/query_gen/get_collocation.py \
        -i $text \
        -w $workdir \
        -n 1

    log "Done. Please check the output file above. You can make edits in it mannualy if needed."
fi
