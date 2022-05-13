#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

################################################
# Get the required nbest dir from kaldi's nbest output
################################################

cmd=queue.pl

data=std2006_dev
kws_exp=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/
nbest_dir=${kws_exp}/nbest_kaldi/
n=100
# datasets="std2006_dev std2006_eval callhome_dev callhome_eval callhome_train"

kaldi_asr=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
oldlang=${kaldi_asr}/data/lang_sw1_fsh_fg

kaldi_model_dir=${kaldi_asr}/exp/chain/tdnn7r_sp/

# for std2006: lmwt=10
# for callhome: lmwt=9
lmwt=10

################################################
# Decode the nbest list from kaldi's decoding dir
################################################

cd $kaldi_asr
[ -f ./path.sh ] && . ./path.sh

acwt=`perl -e "print (1.0/$lmwt);"`
decode_dir=${kaldi_model_dir}/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/
nj=`cat ${decode_dir}/num_jobs` || exit 1;
echo $nj

outputdir=${decode_dir}/nbest/
rm -rf $outputdir
mkdir -p $outputdir
$cmd JOB=1:$nj $outputdir/log/lat2nbest.JOB.log \
    lattice-to-nbest --acoustic-scale=$acwt --n=$n \
    "ark:gunzip -c $decode_dir/lat.JOB.gz|" \
    "ark:|gzip -c >$outputdir/nbest1.JOB.gz" || exit 1;

# view a compact lattice clat
# clat=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_std2006_dev_sw1_fsh_fg_rnnlm_1e_0.45/nbest/nbest1.1.gz
# lattice-copy "ark:gunzip -c $clat |" "ark,t:temp.txt"

adir=$outputdir/archives
$cmd JOB=1:$nj $outputdir/log/make_new_archives.JOB.log \
    mkdir -p $adir.JOB '&&' \
    nbest-to-linear "ark:gunzip -c $outputdir/nbest1.JOB.gz|" \
    "ark,t:$adir.JOB/ali" "ark,t:$adir.JOB/words" \
    "ark,t:$adir.JOB/lm_cost" "ark,t:$adir.JOB/ac_cost" || exit 1;


################################################
# Convert Kaldi's nbest format to our format
################################################

# TODO: May be improved according to https://senarvi.github.io/kaldi-lattices/
# How to obtain the score for hypos in the nbest list: https://groups.google.com/g/kaldi-help/c/hb_VVKVnTpo
$cmd JOB=1:$nj $nbest_dir/log/nbest.JOB.log \
    set -e -o pipefail '&&' \
    mkdir -p $nbest_dir/temp/JOB/ '&&' \
    utils/int2sym.pl -f 2- $oldlang/words.txt \< $adir.JOB/words \> $adir.JOB/words_text '&&' \
    join -j 1 $adir.JOB/{lm_cost,ac_cost} \| awk -v acwt=$acwt "{print \\\$1, (- \\\$2 - \\\$3 * acwt);}" \| \
    join -j 1 \- $adir.JOB/words_text \| awk "{\\\$1=substr(\\\$1, 1, match(\\\$1, /-[^-]*$/)-1)}1" \
    \> $nbest_dir/temp/JOB/nbest.txt || exit 1;

# Note: nbest.txt is of this format:
# (uid, log-prob, sentence)
# In Kaldi, the "log-prob" can be positive, but it does not matter if we normalize the posterior for each sentence

# realpath $adir.$i/words_text
# less $adir.$i/words_text
# less /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_callhome_train_sw1_fsh_fg_rnnlm_1e_0.45/nbest/archives.40/words_text
# vi /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c//exp/chain/tdnn7r_sp/decode_callhome_train_sw1_fsh_fg_rnnlm_1e_0.45//nbest/archives.1/{acwt,lmwt,words_text} -O

for job_id in `seq 1 $nj`; do 
    cut -d' ' -f1 $nbest_dir/temp/$job_id/nbest.txt | sort -u > $nbest_dir/temp/$job_id/utt
    # wc -l $nbest_dir/temp/$job_id/utt
done

echo $nj > $nbest_dir/num_jobs
