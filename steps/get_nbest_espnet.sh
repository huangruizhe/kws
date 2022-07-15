#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

# checkout /export/fs04/a12/rhuang/kws/kws/run_espnet.sh
# TODO: check-in my version of espnet

# begin configuration section.
cmd=run.pl
stage=0
stop_stage=10000
nj=
max_states_scale=-1
max_states=1000000
skip_optimization=false
score_type=
espnet_asr=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
espnet_model="espnet/roshansh_asr_base_sp_conformer_swbd"
#end configuration section.

cd $espnet_asr
[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

# from ESPNet
log() {
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%dT%H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

# Absolute paths are prefered
data=$1
espnet_decode_dir=$2
nbest_dir=$3

# echo "------------------ Parameters ------------------"
# echo nbest_dir: $nbest_dir
# echo data_dir: $data_dir
# echo indices_dir: $indices_dir
# echo scale: $scale
# echo kaldi: $kaldi
# echo montreal: $montreal
# echo "------------------------------------------------"

# cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12

mkdir -p $nbest_dir/log

[[ -z "$nj" ]] && [[ -d $espnet_decode_dir/logdir ]] && nj=`ls -d1 $espnet_decode_dir/logdir/output.* | wc -l`  # espnet
log "num_job: $n"

################################################
# Get the required nbest dir from espnet's nbest output
################################################

# cmd=queue.pl

# data=std2006_dev
# kws_exp=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/
# nbest_dir=${kws_exp}/nbest_espnet/
# n=100
# # datasets="std2006_dev std2006_eval callhome_dev callhome_eval callhome_train"

# espnet_asr=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1

# espnet_decode_dir=${espnet_asr}/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
# # data_dir=data/${data}

################################################
# Data prep
################################################
if [ ${stage} -le -10 ] && [ ${stop_stage} -ge -10 ]; then
    # utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/$data/ data/$data

    # Make features
    bash run.sh --skip_data_prep false \
    --skip_train true \
    --download_model $espnet_model \
    --stage 3 \
    --stop_stage 3 \
    --train_set $data --valid_set "None" --test_sets "None"
fi

################################################
# Decode the nbest list from espnet's model
################################################
if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    # make sure that in "espnet2/bin/asr_inference.py" the "token_list" is correct

    bash run.sh --download_model $espnet_model \
        --test_sets "$data" --skip_data_prep true --skip_train true \
        --inference_args "--nbest $n" --stop_stage 13

    # get kaldi's style WER
    # ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
    # hyp=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/text
    # bash local/score_kaldi_light.sh $ref $hyp data/$data $(dirname "$hyp")

    # Other decoding options:
    # E.g. run ctc decoding
    inference_tag="decode_asr_nbest100_valid.loss.best_asr_model_valid.acc.ave_withoutlm"
    bash run.sh --test_sets "$data" \
        --skip_data_prep true --skip_train true \
        --download_model $espnet_model \
        --inference_tag ${inference_tag} \
        --stop_stage 13 \
        --inference_config "conf/decode_asr_ctc.yaml"
    
    # E.g. run without transformer lm
    # conf/decode_asr_nolm.yaml
fi


################################################
# Convert ESPNet's nbest format to our format
################################################

if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    # First, Obtain word-level confidence scores from token-level scores
    log "score_type: $score_type"
    log "log path: $nbest_dir/log/wscores.1.log"
    time $cmd JOB=1:$nj $nbest_dir/log/wscores.JOB.log \
        set -e -o pipefail '&&' \
        mkdir -p $nbest_dir/temp/JOB/ '&&' \
        bash $func get_w_scores JOB $length_bonus $nbest_dir $score_type
    grep -iF error $nbest_dir/log/wscores.*.log
fi

cd $espnet_asr
conda activate espnet_gpu

montreal=""
kaldi=""
skip_optimization=true
espnet_path=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
dir=${espnet_asr}/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
tgt_dir=${espnet_asr}/kws_indices${kaldi}/${data}_100/
data_dir=data/${data}

montreal=
scale=1.0
kaldi=
dev=
skip_optimization=true
nbest_dir=$dir
indices_dir=$tgt_dir
nj=`ls -d1 $nbest_dir/logdir/output.* | wc -l`
echo $nj

# Obtain word-level confidence scores from token-level scores
length_bonus=0.1
func=/export/fs04/a12/rhuang/kws/kws-release/scripts/nbest2kws_indices_func.sh
cmd=queue.pl
# score_type="ac"  # ['all', 'att', 'ctc', 'lm', 'ac', "all-lb"]
for score_type in 'all' 'att' 'ctc' 'lm' 'ac' "all-lb"; do
    echo "score_type:" $score_type
    echo "log path:" $indices_dir/log/wscores.1.log
    time $cmd JOB=1:$nj $indices_dir/log/wscores.JOB.log \
        set -e -o pipefail '&&' \
        mkdir -p $indices_dir/temp/JOB/ '&&' \
        bash $func get_w_scores JOB $length_bonus $nbest_dir $score_type
    grep -iF error $indices_dir/log/wscores.*.log
done

# some sanity checks
for f in $nbest_dir/logdir/output.28/*best_recog/; do 
    num1=$(wc -l "$f/text" | cut -d' ' -f1)
    num2=$(wc -l "$f/word_score_${score_type}" | cut -d' ' -f1)
    if [[ $num1 -ne $num2 ]]; then
        wc -l "$f/{text,word_score_${score_type}}"
    fi
done

for job_id in `seq 1 $nj`; do 
    nbest=`ls -d1 $nbest_dir/logdir/output.${job_id}/*best_recog | wc -l`
    mkdir -p $indices_dir/temp/${job_id}/
    if [[ ! -f $indices_dir/temp/${job_id}/nbest.txt ]]; then
        (
            for ibest in `seq 1 $nbest`; do 
                [ -f $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/text ] \
                && join -j 1 \
                    <(cut -d' ' -f1,2 $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/score) \
                    $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/text
            done;
        ) | \
        sort -s -k1,1 | \
        awk 'BEGIN{FS=OFS=" ";}{ if(match($2, "tensor")) { $2=substr($2, 8, length($2)-8) }; print}' \
        > $indices_dir/temp/${job_id}/nbest.txt
        echo "Done: " $indices_dir/temp/${job_id}/nbest.txt
    else
        echo "File exists, skipping: " $indices_dir/temp/${job_id}/nbest.txt
    fi

    # process the token-level scores => word-level scores
    # Note: the token-level scores may contain "length-bonus"
    if [[ $(awk 'NR==1{print NF}' $nbest_dir/logdir/output.1/1best_recog/score) -gt 2 ]]; then        
        for score_type in 'all' 'att' 'ctc' 'lm' 'ac' "all-lb"; do     # 'all' 'att' 'ctc' 'lm' 'ac' "all-lb"
            f=$nbest_dir/logdir/output.${job_id}/1best_recog/word_score_${score_type}
            if [ ! -f "$f" ]; then
                echo "$f does not exist"
                continue
            fi 
            
            (
                for ibest in `seq 1 $nbest`; do 
                    [ -f $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/text ] \
                    && join -j 1 \
                        $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/word_score_${score_type} \
                        <(cut -d' ' -f1 $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/text)
                done;
            ) | \
            sort -s -k1,1 \
            > $indices_dir/temp/${job_id}/nbest_w_scores_${score_type}.txt
            echo $indices_dir/temp/${job_id}/nbest_w_scores_${score_type}.txt
        done
    fi
done
echo $nj > $indices_dir/temp/num_jobs
echo "Done."



