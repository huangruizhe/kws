#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
conda activate espnet_gpu
echo $data
montreal=""
# montreal=".montreal"
kaldi=""
skip_optimization=true
espnet_path=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
dir=${espnet_path}/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
tgt_dir=${espnet_path}/kws_indices${kaldi}/${data}_100
# tgt_dir=${espnet_path}/kws_indices${kaldi}/${data}_100_rover5/
data_dir=data/${data}
# kws_scpt=/export/fs04/a12/rhuang/kws/kws/local/nbest2kws_indices1.sh
kws_scpt=/export/fs04/a12/rhuang/kws/kws/local/get_clats.sh
nsize=100

my_tgt_dir=${espnet_path}/kws_indices${kaldi}/${data}_rover5_$nsize

# don't forget the score_type=pos
# need to modify local/rover2.py and local/nbest2kws_indices1.sh
scale=1.0
score_type="_pos"  # it does not matter which you take, we will actually output to "_pos"
time bash $kws_scpt --nsize $nsize --score_type $score_type --montreal "$montreal" --kaldi "$kaldi" --cmd queue.pl --stage 0 --stop_stage 0 --scale $scale $tgt_dir $data_dir $my_tgt_dir

time bash $kws_scpt --nsize $nsize --score_type $score_type --montreal "$montreal" --kaldi "$kaldi" --cmd run.pl --stage 0 --stop_stage 0 --scale $scale $tgt_dir $data_dir $my_tgt_dir

# The scaling factor is only reasonable for pos
for scale in 5.0 2.0 1.5 1.2 1.1 1.0 0.9 0.8 0.7 0.6 0.5 0.4 0.3 0.2 0.1 0.0; do
    echo `date` score_type=$score_type scale=$scale
    score_type="_pos"  # it does not matter which you take, we will actually output to "_pos"
    time bash $kws_scpt --nsize $nsize --score_type $score_type --montreal "$montreal" --kaldi "$kaldi" --cmd run.pl --stage 0 --stop_stage 0 --scale $scale $tgt_dir $data_dir $my_tgt_dir
done

# and really generate the clats
scale=1.0
for score_type in "_all-lb" '_ac' '_att' '_ctc' ; do  # '_all' '_lm' 
    echo `date` score_type=$score_type scale=$scale
    time bash $kws_scpt --nsize $nsize --score_type $score_type --montreal "$montreal" --kaldi "$kaldi" --cmd run.pl --stage 0 --stop_stage 0 --scale $scale $tgt_dir $data_dir $my_tgt_dir
done

