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
# keywords=/export/fs04/a12/rhuang/kws/kws/data0/$data/kws/keywords.$data.txt     # std2006
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
# export PYTHONPATH=$PYTHONPATH:/export/fs04/a12/rhuang/espnet/
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

# scoring max_distance 50 100 500
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
data=callhome_dev
nbest_dir=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/nbest_topk/
nbest_dir=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/nbest_espnet1.0
nbest_dir=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/nbest_kaldi/
nsize=50
bash /export/fs04/a12/rhuang/kws/kws-release/scripts/oracle_wer.sh \
  --ref /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt \
  --nbest_dir $nbest_dir \
  --nsize $nsize  \
  --stage 2

################################################
# analysis
################################################

grep KW-00069 /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk//kws_indices/kws_results/details_50/per-category-score.txt
grep KW-00069 /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_kaldi//kws_indices/kws_results/details_50/per-category-score.txt

# KW-00007	english
ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
kw=english
# kwid=KW-00007
kwid=$(grep "$kw" $kws_data_dir/keywords.txt | cut -f1)
grep --color $kw $ref
grep --color $kwid /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk//kws_indices/kws_results/details_50/alignment.csv
grep --color $kwid /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_kaldi//kws_indices/kws_results/details_50/alignment.csv

grep 5202 $kws_data_dir/utt.map

# replace id with uid
# nice!
grep $kwid /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_kaldi//kws_indices/kws_results/details_50/alignment.csv \
  | cut -d',' -f2 | utils/int2sym.pl -f 1  /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_callhome_dev/utt.map -

show_alignment () {
    _kws_data_dir=$1
    _kwid=$2
    _alignment=$3
    
    echo $_alignment
    paste -d" " \
    <(grep $_kwid $_alignment | cut -d',' -f2 | utils/int2sym.pl -f 1  $_kws_data_dir/utt.map -) \
    <(grep $_kwid $_alignment) | \
    grep --color $_kwid
}
kwid=KW-00007
alignment=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk//kws_indices/kws_results/details_50/alignment.csv
kws_data_dir=/export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_callhome_dev
show_alignment $kws_data_dir $kwid $alignment

# ground truth transcription
uid=en_4157_0A_00133
grep $uid data/$data/text
grep $uid $ref

# nbest list
grep -h $uid data/callhome_dev/text
grep -h $uid $ref
grep -h $uid /export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_kaldi/nbest/*/nbest.txt | head -$nsize | nl
grep -h $uid /export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_topk/nbest/*/nbest.txt | head -$nsize | nl

grep -h $uid /export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_topk/nbest/*/token.txt | head -$nsize | nl

grep -h $uid /export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_kaldi/temp/*/scoring_kaldi/hyp.text

# clat
job_id=33
vi /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_kaldi/clat_eps2/clat.${job_id}.eps2.gz
vi /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk/clat_eps2/clat.${job_id}.eps2.gz

# raw results (before filtering and kst)
vi /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_kaldi/kws_indices/kws_results/result.${job_id}.gz
vi /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk/kws_indices/kws_results/result.${job_id}.gz

### result 1 ###
# 发现是deduplication algorithm有问题
# 因为espnet生成的nbest较为冗余和混乱，例如：
# en_4157_0A_00133-6201 that is good do they speak english
# en_4157_0A_00133-6248 that is good do they speak english english and
# 导致在生成lattice/CN时，产生冗余
# KW-00007 468 100 134 0
# KW-00007 468 134 137 10.73926
# KW-00007 468 99 100 18.80859
# 这种冗余性在查找时，才被filter掉

vimdiff local/kws/filter_kws_results.pl /export/fs04/a12/rhuang/kaldi_latest/kaldi/egs/mini_librispeech/s5/local/kws/filter_kws_results.pl

### result 2 ###
# fix the problem with https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5d/local/search/per_category_stats.pl#L236
# WRONG:
# my $stwv = 1 - $STATS{$kw}->{lattice_miss}/$STATS{$kw}->{ntrue};
# SHOULD BE:
# my $stwv = 1 - $STATS{$kw}->{miss}/$STATS{$kw}->{ntrue};
#----------------------------------------------------------------
# No. The above fix is not correct. The original scripts are correct, instead.
# Note, there are two kinds of misses:
# 1) The kw presents in the lattice/nbest, but it is not detected as the score is too low. (miss)
# 2) The kw does not present in the lattice/nbest at all. (lattice_miss)

# check bpe encoding
export PYTHONPATH=$PYTHONPATH:/export/fs04/a12/rhuang/espnet/
python
from espnet2.text.sentencepiece_tokenizer import SentencepiecesTokenizer
bpemodel="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/en_token_list/bpe_unigram2000/bpe.model"
tokenizer = SentencepiecesTokenizer(bpemodel)
# /export/fs04/a12/rhuang/espnet/espnet2/text/sentencepiece_tokenizer.py
text=""
tokenizer.text2tokens(text)

# The beam search results can be quite redandant:
kw=shit
kwid=KW-00031
grep -h en_4686_0B_00288 /export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_topk/nbest/*/nbest.txt
grep -h en_4686_0B_00288 /export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_topk/nbest/*/token.txt


# How many lattice-miss hits are actually appear in the hypothesis?
python /export/fs04/a12/rhuang/kws/kws-release/scripts/alignment_miss_analysis.py \
  --keywords /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_callhome_dev/keywords.txt \
  --utt_map /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_callhome_dev/utt.map \
  --alignment /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk//kws_indices/kws_results/details_50/alignment.csv

# get word frequency list in a recording or nbest list
recording_id=en_4686_0B   # en_4686_0B_00288 shit
grep $recording_id data/callhome_dev/text | cut -d" " -f2-
grep $recording_id data/callhome_dev/text | cut -d" " -f2- | \
  tr ' ' '\n' | sort | uniq -c | sort -r # | awk '{print $2"@"$1}'

# frequency from nbest list
nbest_list='/export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_topk/nbest/*/nbest.txt'
grep -h $recording_id $nbest_list | wc
grep -h $recording_id $nbest_list | \
  grep ship | wc
grep -h $recording_id $nbest_list | \
  grep shit | wc

grep -h $uid /export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_topk/nbest/*/nbest.txt



alignment=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk//kws_indices/kws_results/details_50/alignment.csv
kw=psychologist
# grep $kw $kws_data_dir/keywords.txt
kw_id=$(grep "$kw" $kws_data_dir/keywords.txt | cut -f1)
grep $kw  $ref
grep --color $kw_id $alignment
show_alignment $kws_data_dir $kwid $alignment
# 发现是timing的问题。。。

uid=en_4315_0B_00011
nbest='/export/fs04/a12/rhuang/kws/kws-release/exp/callhome_dev/nbest_topk/nbest/*/nbest.txt'
grep -h $uid $nbest | head -$nsize | nl

recording_id=en_4315_0B
job_id=5
clat=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk/clat_eps2/clat.${job_id}.eps2.gz
