#!/bin/bash
# Copyright (c) 2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

kaldi_path=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
cd $kaldi_path

# Convert decode_dir to nbest_dir
# Input: decode_dir
# Output: work_dir/nbest_dir

work_dir=
decode_dir=
nbest_dir=
lats_dir=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_$data_${scale}_${nsize}
kws_data_dir=/export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_$data
keywords=/export/fs04/a12/rhuang/kws/kws/data0/$data/kws/keywords.$data.txt     # std2006
keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt  # callhome
scale=1.0
nsize=50
max_distance=



# Input:
# Output: work_dir/kws_data

# Input: work_dir/nbest_dir
# Output: work_dir/lats_dir

# Input: work_dir/lats_dir
# Output: work_dir/lats_dir/indices/results