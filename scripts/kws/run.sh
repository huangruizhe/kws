#!/bin/bash
# Copyright (c) 2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0


cd /export/fs04/a12/rhuang/kws/kws-release

indices_dir=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices_kaldi/std2006_dev_100/
for i in `seq 1 50`; do
    cp $indices_dir/temp/$i/clat.scale1.0.gz /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir/clat.$i.gz
done

# cp /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/kws/{words.txt,utt.map} test/kws_data_dir/.

bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/prep_kws.sh \
  --data std2006_dev \
  --keywords /export/fs04/a12/rhuang/kws/kws/data0/std2006_dev/kws/keywords.std2006_dev.txt \
  --create_catetories "false" \
  --kws_data_dir /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir2

# stage 0 1
tag="_${scale}_${nsize}"
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/make_index.sh \
 --lats_dir /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir${tag} \
 --kws_data_dir /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir2 \
 --frame_subsampling_factor 1 \
 --stage 0
  
# stage 3 4
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/search.sh \
 --lats_dir /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir${tag} \
 --kws_data_dir /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir2 \
 --frame_subsampling_factor 1 \
 --stage 3

# max_distance 50 100 500
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/score.sh \
 --lats_dir /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir${tag} \
 --kws_data_dir /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir2 \
 --max_distance 50

# get ctm file
test_set=std2006_dev
decode=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${test_set}_sw1_fsh_fg_rnnlm_1e_0.45/
steps/get_ctm_conf.sh data/std2006_dev data/lang $decode

# use ntrue from dev for eval
dev_dir=
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/score.sh \
 --lats_dir /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir \
 --kws_data_dir /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir2 \
 --ntrue_from $dev_dir
 --max_distance 50

# How to replicate this result:
# /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_std2006_dev_sw1_fsh_fg_rnnlm_1e_0.45/kws_2_50_kaldi_1.0_eps2/details/score.txt
# https://docs.google.com/spreadsheets/d/1Hd5kXimgxZSbueveNT9dc3grL_B7fxsSL-aAMqD49wk/edit#gid=570879841

# Let me replicate this result: kaldi's 50-best kws


/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_std2006_eval_sw1_fsh_fg_rnnlm_1e_0.45/kws_2_50_kaldi_1.0_eps2/details/score.txt

################################################
# Full process
################################################

data=std2006_dev
data=std2006_eval

nbest_dir=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/nbest_kaldi/
nbest_dir=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/nbest_espnet0.8/
kws_data_dir=/export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_$data
keywords=/export/fs04/a12/rhuang/kws/kws/data0/$data/kws/keywords.$data.txt     # std2006
keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt  # callhome
scale=1.0
nsize=50
lats_dir=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_${data}_${scale}_${nsize}


# get nbest from kaldi's decode directory
/export/fs04/a12/rhuang/kws/kws-release/steps/get_nbest_kaldi.sh
# OR, get nbest from espnet's decode directory (step 0, 1)
/export/fs04/a12/rhuang/kws/kws-release/steps/get_nbest_espnet.sh

# get timing for the nbest
bash /export/fs04/a12/rhuang/kws/kws-release/steps/get_time_kaldi.sh \
 --data $data \
 --nbest_dir $nbest_dir \
 --tag "espnet1.2"

# get confidence scores for nbest
# TODO

# prep kws dir
kaldi_path=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
cd $kaldi_path
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/prep_kws.sh \
  --data $data \
  --keywords $keywords \
  --create_catetories "false" \
  --kws_data_dir $kws_data_dir
cd -

# get clats from nbest
bash /export/fs04/a12/rhuang/kws/kws-release/steps/get_confusion_network.sh \
  --nsize $nsize \
  --nbest_dir $nbest_dir \
  --lats_dir $lats_dir \
  --kws_data_dir $kws_data_dir \
  --ali ${nbest_dir}/timing/1best.ali_kaldi.txt \
  --score_type "_pos" \
  --scale $scale

# stage 0 1
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/make_index.sh \
 --lats_dir $lats_dir \
 --kws_data_dir $kws_data_dir \
 --frame_subsampling_factor 1 \
 --stage 0
  
# stage 3 4
cd $kaldi_path
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/search.sh \
 --lats_dir $lats_dir \
 --kws_data_dir $kws_data_dir \
 --frame_subsampling_factor 1 \
 --stage 3
cd -

# max_distance 50 100 500
cd $kaldi_path
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/score.sh \
 --lats_dir $lats_dir \
 --kws_data_dir $kws_data_dir \
 --max_distance 50
cd -

# check scores:
f=$lats_dir//kws_indices/kws_results/details_50/score.txt
# cat $f
readarray -t results < <(cat $f | rev | cut -d' ' -f1 | rev); echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}

# use ntrue from dev for eval
dev_dir=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir/kws_indices/kws_results/details_50/
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/score.sh \
 --lats_dir $lats_dir \
 --kws_data_dir $kws_data_dir \
 --ntrue_from $dev_dir
 --max_distance 50


# oracle WER
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/oracle_wer.sh \
  --ref /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt \
  --nbest_dir $nbest_dir \
  --nsize $nsize  
