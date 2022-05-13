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

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
score_type="_pos"     # "_pos" '_all' "_all-lb" '_lm' '_ac' '_att' '_ctc' 
max_distance_range="25 50 500"     # "25 50 500"
sweep_step=0.005
# sweep_step=0.0001
for scale in 1.0; do
# for scale in 5.0 2.0 1.5 1.2 1.1 1.0 0.9 0.8 0.7 0.6 0.5 0.3 0.0; do
    time bash $fix_long_dur_script --cmd run.pl --score_type $score_type --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 0

    time bash $fix_long_dur_script --cmd run.pl --score_type $score_type --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 1 --skip_optimization "$skip_optimization"
    [[ -d $indices_dir/kws_indices_2_${scale}${montreal}${score_type}_eps2 ]] && rm -r $indices_dir/kws_indices_2_${scale}${montreal}${score_type}_eps2
    mv $indices_dir/kws_indices $indices_dir/kws_indices_2_${scale}${montreal}${score_type}_eps2; echo $indices_dir/kws_indices_2_${scale}${montreal}${score_type}_eps2

    # You may probably need to generate the keyword fsts

    bash $fix_long_dur_script --cmd run.pl --score_type $score_type --create_catetories "true" --max_distance_range "$max_distance_range" --sweep-step ${sweep_step} --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3  
done

for score_type in '_pos' '_all-lb' '_ac' '_att' '_ctc'; do  # '_all' '_lm' 
    echo "====== score_type: $score_type ======" `date`
    max_distance_range="25 50 500"     # "25 50 500"
    scale=1.0
    # sweep_step=0.0001
    sweep_step=0.005
    time bash $fix_long_dur_script --score_type $score_type --create_catetories "true" --max_distance_range "$max_distance_range" --sweep-step ${sweep_step} --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3  
done

