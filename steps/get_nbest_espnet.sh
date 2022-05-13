#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

################################################
# Get the required nbest dir from espnet's nbest output
################################################

cmd=queue.pl

data=std2006_dev
kws_exp=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/
nbest_dir=${kws_exp}/nbest_espnet/
n=100
# datasets="std2006_dev std2006_eval callhome_dev callhome_eval callhome_train"

espnet_asr=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1

decode_dir=${espnet_asr}/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
# data_dir=data/${data}

################################################
# Decode the nbest list from espnet's model
################################################

# TODO: check-in my version of espnet

# /export/fs04/a12/rhuang/kws/kws/run_espnet.sh

cd $espnet_asr
conda activate espnet_gpu

# first go to "espnet2/bin/asr_inference.py" to modify about "token_list"
bash run.sh --skip_data_prep true \
    --skip_train true \
    --download_model espnet/roshansh_asr_base_sp_conformer_swbd \
    --stop_stage 12

# debugged for 5 hours to finally being able to run the model

# make features
utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/std2006_dev/ data/std2006_dev
utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/std2006_eval/ data/std2006_eval
# d=train; utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/callhome_${d} data/callhome_${d}
d=dev; utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/callhome_${d} data/callhome_${d}
d=eval; utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/callhome_${d} data/callhome_${d}

# for callhome path
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
ln -s /export/corpora5/LDC/LDC97S42/ .

vi run.sh
# set the following:
test_sets="std2006_dev std2006_eval callhome_dev callhome_eval"
# modify "Stage 3" in asr.sh to skip train_set, valid_set
# then run:
bash run.sh --skip_data_prep false \
    --skip_train true \
    --download_model espnet/roshansh_asr_base_sp_conformer_swbd \
    --stage 3 \
    --stop_stage 3

# decoding
# To save time, it is better to run each dataset on one machine
pretrained="espnet/roshansh_asr_base_sp_conformer_swbd"
test_set=
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --stop_stage 12 # --gpu_inference true

# scoring
test_sets="std2006_dev std2006_eval"
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --stage 13 --stop_stage 13

# get nbest
n=100
test_sets=std2006_dev
test_sets=std2006_eval
test_sets=callhome_dev
test_sets=callhome_eval
bash run.sh --download_model $pretrained \
    --test_sets "$test_sets" --skip_data_prep true --skip_train true \
    --inference_args "--nbest $n" --stop_stage 12

# get WER
data=$test_sets
ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
datadir=data/${data}/
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
hyp=$decode/text
bash local/score_kaldi_light.sh $ref $hyp $datadir $decode

# run without transformer lm
# edit run.sh to use "inference_config=conf/decode_asr_nolm.yaml"
inference_tag="decode_asr_nbest100_valid.loss.best_asr_model_valid.acc.ave_withoutlm"
test_sets=eval2000
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --inference_tag ${inference_tag} \
    --stop_stage 12

# run ctc decoding
# edit run.sh to use "inference_config=conf/decode_asr_ctc.yaml"
inference_tag="decode_asr_nbest100_valid.loss.best_asr_model_valid.acc.ave_ctc"
test_sets=eval2000
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --inference_tag ${inference_tag} \
    --stop_stage 12


# scoring
test_sets=eval2000
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --inference_tag ${inference_tag} \
    --stage 13 --stop_stage 13

################################################
# Convert ESPNet's nbest format to our format
################################################

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