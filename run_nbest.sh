#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

stage=0
stop_stage=10000
nj=


##############################
# Generate a list of keywords as search terms
##############################
if [ ${stage} -le -11 ] && [ ${stop_stage} -ge -11 ]; then
    steps/get_keywords.sh
fi

##############################
# Generate nbest list from either Kaldi, ESPNET
##############################
if [ ${stage} -le -10 ] && [ ${stop_stage} -ge -10 ]; then
    steps/get_nbest_kaldi.sh
    steps/get_nbest_espnet.sh
    steps/get_nbest_k2.sh

    # intrinsic analysis
    steps/analysis_nbest.sh
    steps/analysis_cm.sh
fi

##############################
# Get time alignment of the 1st best hypothesis
##############################
if [ ${stage} -le -9 ] && [ ${stop_stage} -ge -9 ]; then
    steps/get_time_kaldi.sh
    steps/get_time_montreal.sh
    steps/get_time_k2.sh

    # intrinsic analysis
    steps/analysis_time.sh
fi

##############################
# Generate sausage with the nbest list
##############################
if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    score_type="ctc"
    steps/get_confusion_network.sh $score_type
fi

##############################
# KWS
##############################
if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    steps/kws_build_indices_from_sausages.sh
    steps/kws_search.sh
fi

# November/December: reasonable Kaldi/ESPNET ASR results, e.g wer_output_filter
# January: timing information, running KWS system for E2E ASR + many fixes (e.g. semiring), analysis (where does the differences come from)
# Feburary: k2 decoding
# March: paper, intrinsic evaluation, extrinsic evaluation, MLE of scaling factor, new espnet's model
# April: intrinsic eval of confidence measures
# May: RNNT decoder, k2 lattice (MBR on k2's lattices), recall


