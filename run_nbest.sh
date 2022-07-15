#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

stage=0
stop_stage=10000
nj=


############################################################
# Generate a list of keywords as search terms
############################################################
if [ ${stage} -le -11 ] && [ ${stop_stage} -ge -11 ]; then
    steps/get_keywords.sh
fi

############################################################
# Generate nbest list and get the nbest directory structure
############################################################
if [ ${stage} -le -10 ] && [ ${stop_stage} -ge -10 ]; then
    steps/decode_kaldi.sh
    steps/decode_espnet.sh

    steps/get_nbest_kaldi.sh
    steps/get_nbest_espnet.sh
    steps/get_nbest_k2.sh

    # intrinsic analysis
    steps/analysis_nbest.sh
    steps/analysis_cm.sh
fi

############################################################
# Get time alignment of the 1st best hypothesis
############################################################
if [ ${stage} -le -9 ] && [ ${stop_stage} -ge -9 ]; then
    steps/get_time_kaldi.sh
    steps/get_time_montreal.sh
    steps/get_time_k2.sh

    # intrinsic analysis
    steps/analysis_time.sh
fi

############################################################
# Generate sausage with the nbest list
############################################################
if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    score_type="ctc"
    steps/get_confusion_network.sh $score_type
fi

############################################################
# Perform KWS
############################################################
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    steps/kws_build_indice_from_cn.sh
    steps/kws_search.sh
fi

