#!/bin/bash
# Copyright (c) 2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

# Ref:
# /export/fs04/a12/rhuang/kws/kws/local/exp-20220720.sh
# /export/fs04/a12/rhuang/kws/kws/local/get_clats.sh

# begin configuration section.
cmd=run.pl
scale=1.0
stage=0
stop_stage=10000
nj=

max_states_scale=-1
max_states=1000000
skip_optimization=false

score_type=
nsize=

nbest_dir=
lats_dir=
kws_data_dir=
ali=
#end configuration section.

# [ -f ./path.sh ] && . ./path.sh
[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;


echo "------------------ Parameters ------------------"
echo nbest_dir: $nbest_dir
echo lats_dir: $lats_dir
echo kws_data_dir: $kws_data_dir
echo ali: $ali
echo score_type: $score_type
echo scale: $scale
echo nsize: $nsize
echo "------------------------------------------------"

[[ -z "$nj" ]] && [[ -f $nbest_dir/num_jobs ]] && nj=`cat $nbest_dir/num_jobs`
mkdir -p $lats_dir
echo $nj > $lats_dir/num_jobs


##############################
# Convert nbest to sausage
##############################
if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    echo "Stage 0: Convert nbest to lattice"

    compressor=gzip
    # compressor=cat

    utt2dur=$kws_data_dir/utt2dur
    words=$kws_data_dir/words.txt

    echo "Using aligment: `wc $ali`" 

    mkdir -p ${lats_dir}/clat/

    # script=/export/fs04/a12/rhuang/kws/kws/local/rover5.py
    script=/export/fs04/a12/rhuang/kws/kws/local/rover6.py
    $cmd JOB=1:$nj ${lats_dir}/log/nbest2lat.JOB.log \
        /export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet_gpu/bin/python3 \
          $script --workdir ${nbest_dir}/nbest/JOB/ \
          --score_type $score_type \
          --dur $utt2dur \
          --words $words \
          --ali $ali \
          --scale $scale \
          --nsize $nsize $other_opts \| \
         $compressor \> ${lats_dir}/clat/clat.JOB.gz || exit 1; 

    grep -iF "error" ${lats_dir}/log/nbest2lat.*.log
    grep -iF "warning" ${lats_dir}/log/nbest2lat.*.log
    echo "Done: `ls -lah ${lats_dir}/clat/clat.1.gz`"
fi

exit 0;


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

