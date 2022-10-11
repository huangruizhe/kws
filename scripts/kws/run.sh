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
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/make_index.sh \
 --lats_dir /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir \
 --kws_data_dir /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir2 \
 --stage 0
  
# stage 3 4
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/search.sh \
 --lats_dir /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir \
 --kws_data_dir /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir2 \
 --stage 3

# max_distance 50 100 500
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/score.sh \
 --lats_dir /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir \
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