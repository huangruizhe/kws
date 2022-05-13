#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
fix_long_dur_script=/export/fs04/a12/rhuang/kws/kws/local/fix_long_dur.sh
echo $data
montreal=
# montreal=".montreal"
scale=1.0
kaldi=
dev=
skip_optimization=true

nbest_dir=$dir
indices_dir=$my_tgt_dir

# if you have already built the index, and just want to re-run the the "search" phase of kws
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
score_type="_all"     # '_all' '_att' '_ctc' '_lm' '_ac' "_all-lb" "_pos"
max_distance_range="25 50 500"     # "25 50 500"
scale=1.0
# sweep_step=0.0001
sweep_step=0.005
time bash $fix_long_dur_script --score_type $score_type --create_catetories "true" --max_distance_range "$max_distance_range" --sweep-step ${sweep_step} --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3  

for score_type in '_pos' '_all-lb' '_ac' '_att' '_ctc'; do  # '_all' '_lm' 
    echo "====== score_type: $score_type ======" `date`
    max_distance_range="25 50 500"     # "25 50 500"
    scale=1.0
    # sweep_step=0.0001
    sweep_step=0.005
    time bash $fix_long_dur_script --score_type $score_type --create_catetories "true" --max_distance_range "$max_distance_range" --sweep-step ${sweep_step} --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3  
done


# Finally, don't forget to use dev ntrue on eval set, copied from local/exp-20210204.sh

# For espnet -- eval with ntrue from dev
cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
fix_long_dur_script=/export/fs04/a12/rhuang/kws/kws/local/fix_long_dur.sh
echo $data
montreal=
# montreal=".montreal"
scale=1.0
kaldi=
# kaldi="_kaldi"
# kaldi="_k2"
dev=
skip_optimization=true

espnet_path=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
# nbest_dir=${espnet_path}/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
# indices_dir=${espnet_path}/kws_indices${kaldi}/${data}_100/

nbest_dir=$dir
indices_dir=$my_tgt_dir

# Run basic kws for both dev and eval
# You may not need to run them -- because the results may have already existed
bash $fix_long_dur_script --score_type $score_type --create_catetories "true" --max_distance_range "25 50 500" --sweep-step ${sweep_step} --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3  

# run with dev ntrue value
dev=std2006_dev; eval=std2006_eval
dev=callhome_dev; eval=callhome_eval

expid=2
eps2_suffix=_eps2
system_dev=exp/chain/tdnn7r_sp/decode_${dev}_sw1_fsh_fg_rnnlm_1e_0.45/
system_eval=exp/chain/tdnn7r_sp/decode_${eval}_sw1_fsh_fg_rnnlm_1e_0.45/
score_type="_pos"
sweep_step=0.005
cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
for score_type in '_pos' '_all-lb' '_ac' '_att' '_ctc'; do  # '_all' '_lm' 
    echo "====== score_type: $score_type ======" `date`
    for max_distance in 25 50 500; do
        echo "----max_distance = $max_distance----"

        tgt=kws_${expid}_${max_distance}${kaldi}${montreal}${score_type}${eps2_suffix}
        # echo "tgt:" $tgt
        rm -rf $system_dev/kws_2
        rm -rf $system_eval/kws_2
        ln -s $tgt $system_dev/kws_2
        ln -s $tgt $system_eval/kws_2

        echo "----eval----"
        echo "Using ntrue from:" $(realpath ${system_dev}/kws_${expid})
        time bash local/kws/score_nbest.sh  --cmd run.pl --min-lmwt $expid --max-lmwt $expid \
            --max_distance ${max_distance} \
            --ntrue_from ${system_dev}/kws \
            --sweep-step $sweep_step \
            data/lang data/${eval} ${system_eval}/kws
        
        f=${system_eval}/kws_${expid}/details/score.txt
        readlink -f $f
        echo max_distance=$max_distance "eval"
        readarray -t results < <(cat $f | rev | cut -d' ' -f1 | rev); echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}
    done
done
