#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

############################################################
# Kaldi's default KWS
############################################################

# local/exp-20210204.sh

# Note: 
# (1) Don't forget to check Kaldi's src codes, and use the original ones (replace files and make/compile!)
# src/kwsbin/lattice-to-kws-index-0707-for-e2e-kws.cc
# src/kws/kws-functions-0707-for-e2e-kws.cc
# (2) You may need to run the alignment step in run_kws_std2006.sh

# make file
# cd $KALDI_ROOT
# git st
# cp src/kws/kws-functions-0707-for-e2e-kws.cc src/kws/kws-functions.cc
# cp src/kwsbin/lattice-to-kws-index-0707-for-e2e-kws.cc src/kwsbin/lattice-to-kws-index.cc
# cd src/kws/; make; cd -
# cd src/kwsbin/; make; cd -

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c

data=
max_distance=

# std2006
keywords=/export/fs04/a12/rhuang/kws/kws/data0/${data}/kws/keywords.${data}.txt  # NIST
# std2006 and callhome
keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt  # PMI
wc $keywords

time bash local/kws/run_kws_std2006.sh \
  --data data/${data} \
  --keywords ${keywords} \
  --output data/${data}/kws/ \
  --system exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/ \
  --max-distance $max_distance   # --stage 5   # with stage=5, we will run search.sh only, skipping building index

# decode_dir=exp/chain/tdnn7r_sp/decode_eval2000_sw1_fsh_fg_rnnlm_1e_0.45
# find $decode_dir -name "score.txt" -ipath '*/details/*' | xargs cat | grep ATWV | sort | tail -n 1
# find $decode_dir -name "score.txt" -ipath '*/details/*' | xargs grep 0.9041

decode_dir=exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/
(for lmwt in 8 9 10 11 12 13 14; do
	echo $decode_dir/kws_${lmwt}/details/score.txt
done;) | xargs cat | grep ATWV | sort | tail -n 1
find $decode_dir -name "score.txt" -ipath '*/details/*' | xargs grep  0.9041

f=
readarray -t results < <(cat $f | rev | cut -d' ' -f1 | rev); echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}

################################################
# For kaldi's default kws -- eval with ntrue from dev

# First, run the above steps (default kws) for both dev and eval
# Then in the "data=eval" window, run the following:

dev=std2006_dev; eval=std2006_eval
dev=callhome_dev; eval=callhome_eval

system_dev=exp/chain/tdnn7r_sp/decode_${dev}_sw1_fsh_fg_rnnlm_1e_0.45/
system_eval=exp/chain/tdnn7r_sp/decode_${eval}_sw1_fsh_fg_rnnlm_1e_0.45/

expid=12  # std2006
expid=9  # callhome

# for max_distance in 25 50 500; do
echo "----max_distance = $max_distance, expid = $expid ----"
echo "----eval----"
echo "Using ntrue from:" $(realpath ${system_dev}/kws_${expid})
time bash local/kws/score_nbest.sh  --cmd run.pl --min-lmwt $expid --max-lmwt $expid \
    --max_distance ${max_distance} \
    --ntrue_from ${system_dev}/kws \
    data/lang data/${eval} ${system_eval}/kws

f=${system_eval}/kws_${expid}/details/score.txt
readlink -f $f
echo max_distance=$max_distance "eval"
readarray -t results < <(cat $f | rev | cut -d' ' -f1 | rev); echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}
    
