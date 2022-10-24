#!/bin/bash
# Copyright (c) 2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

# Get oracle WER of a nbest_dir

# Ref:
# /export/fs04/a12/rhuang/kws/kws/local/oracle_wer.ipynb
# /export/fs04/a12/rhuang/kws/kws/local/oracle_wer.sh

ref=
nbest_dir=
lats_dir=
nsize=

cmd=run.pl
stage=0
stop_stage=10000
nj=

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}


[[ -z "$nj" ]] && [[ -f $nbest_dir/num_jobs ]] && nj=`cat $nbest_dir/num_jobs`

log "------------------ Parameters ------------------"
log ref: $ref
log nbest_dir: $nbest_dir
log lats_dir: $lats_dir
log nsize: $nsize
log nj: $nj
log "------------------------------------------------"

py=/export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet_gpu/bin/python

if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    log "Stage 0: Generate references for nbest list"

    script=/export/fs04/a12/rhuang/kws/kws-release/scripts/get_ref_for_nbest.py
    $cmd JOB=1:$nj $nbest_dir/log/oracle_wer.JOB.log \
        set -e -o pipefail '&&' \
        mkdir -p ${nbest_dir}/temp/JOB/scoring_kaldi '&&' \
        $py $script --text $ref \
            --nbest ${nbest_dir}/nbest/JOB/nbest.txt \
            --ref ${nbest_dir}/temp/JOB/scoring_kaldi/ref.nbest.txt \
            --hyp ${nbest_dir}/temp/JOB/scoring_kaldi/hyp.nbest.txt \
            --get_ref_no_scores
    grep -iF error $nbest_dir/log/oracle_wer.*.log
fi

if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    log "Stage 1: Compute WER with kaldi's scoring tool"

    [ -f ./path.sh ] && . ./path.sh
    ref_filtering_cmd="cat"
    [ -x local/wer_output_filter ] && ref_filtering_cmd="local/wer_output_filter"
    [ -x local/wer_ref_filter ] && ref_filtering_cmd="local/wer_ref_filter"
    hyp_filtering_cmd="cat"
    [ -x local/wer_output_filter ] && hyp_filtering_cmd="local/wer_output_filter"
    [ -x local/wer_hyp_filter ] && hyp_filtering_cmd="local/wer_hyp_filter"

    log "ref_filtering_cmd=${ref_filtering_cmd}"
    log "hyp_filtering_cmd=${hyp_filtering_cmd}"

    # time for job_id in `seq 1 $nj`; do 
    #     log `date` "===== $job_id ====="

    #     scoring_dir=${nbest_dir}/temp/${job_id}/scoring_kaldi
        # ref_text=${scoring_dir}/ref.nbest.txt
        # hyp_text=${scoring_dir}/hyp.nbest.txt

        # cat $ref | $ref_filtering_cmd > ${scoring_dir}/ref.1best.text
        # cat $ref_text | $ref_filtering_cmd > ${scoring_dir}/ref.text
        # cat $hyp_text | $hyp_filtering_cmd > ${scoring_dir}/hyp.text

        # mkdir -p ${scoring_dir}/wer_details

    #     cat ${scoring_dir}/hyp.text | \
    #         align-text --special-symbol="'***'" ark:${scoring_dir}/ref.text ark:- ark,t:- |  \
    #         utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" > ${scoring_dir}/wer_details/per_utt
    #     realpath ${scoring_dir}/wer_details/per_utt
    # done

    $cmd JOB=1:$nj $nbest_dir/log/per_utt.JOB.log \
        set -e -o pipefail '&&' \
        scoring_dir=${nbest_dir}/temp/JOB/scoring_kaldi '&&' \
        cat \${scoring_dir}/ref.nbest.txt \| $ref_filtering_cmd \> \${scoring_dir}/ref.text '&&' \
        cat \${scoring_dir}/hyp.nbest.txt \| $hyp_filtering_cmd \> \${scoring_dir}/hyp.text '&&' \
        mkdir -p \${scoring_dir}/wer_details '&&' \
        cat \${scoring_dir}/hyp.text \| \
            align-text --special-symbol="'***'" ark:\${scoring_dir}/ref.text ark:- ark,t:- \|  \
            utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" \> \${scoring_dir}/wer_details/per_utt
    grep -iF error $nbest_dir/log/per_utt.*.log
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    log "Stage 2: Compute Oracle WER"

    script=/export/fs04/a12/rhuang/kws/kws-release/scripts/oracle_wer.py
    $py $script --oracle_wer \
        --text $ref \
        --per_utt ${nbest_dir}/temp/'*'/scoring_kaldi/wer_details/per_utt \
        --n $nsize \
        --nbest ${nbest_dir}/nbest/'*'/nbest.txt
fi

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    if [ -f $lats_dir//kws_indices/kws_results/results ]; then
        log "Stage 3: Length of the putative hitlist"
        wc wc $lats_dir//kws_indices/kws_results/results
    fi
fi
