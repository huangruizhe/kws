#!/bin/bash
# Copyright (c) 2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

################################################
# Get the required nbest dir from kaldi's nbest output
################################################

# Reference: /export/fs04/a12/rhuang/kws/kws/local/nbest2kws_indices1.sh

cmd=queue.pl

data=std2006_dev
data=std2006_eval
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
nj=`cat ${decode_dir}/num_jobs`
echo $nj

outputdir=${decode_dir}/nbest/
outputdir=${decode_dir}/nbest2/
# rm -rf $outputdir
mkdir -p $outputdir
$cmd JOB=1:$nj $outputdir/log/lat2nbest.JOB.log \
    lattice-to-nbest --acoustic-scale=$acwt --n=$n \
    "ark:gunzip -c $decode_dir/lat.JOB.gz|" \
    "ark:|gzip -c >$outputdir/nbest1.JOB.gz"

# view a compact lattice clat
# clat=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_std2006_dev_sw1_fsh_fg_rnnlm_1e_0.45/nbest/nbest1.1.gz
# lattice-copy "ark:gunzip -c $clat |" "ark,t:temp.txt"

adir=$outputdir/archives
$cmd JOB=1:$nj $outputdir/log/make_new_archives.JOB.log \
    mkdir -p $adir.JOB '&&' \
    nbest-to-linear "ark:gunzip -c $outputdir/nbest1.JOB.gz|" \
    "ark,t:$adir.JOB/ali" "ark,t:$adir.JOB/words" \
    "ark,t:$adir.JOB/lm_cost" "ark,t:$adir.JOB/ac_cost"


################################################
# Convert Kaldi's nbest format to our format
################################################

# TODO: May be improved according to https://senarvi.github.io/kaldi-lattices/
# How to obtain the score for hypos in the nbest list: https://groups.google.com/g/kaldi-help/c/hb_VVKVnTpo
$cmd JOB=1:$nj $nbest_dir/log/nbest.JOB.log \
    set -e -o pipefail '&&' \
    mkdir -p $nbest_dir/nbest/JOB/ '&&' \
    utils/int2sym.pl -f 2- $oldlang/words.txt \< $adir.JOB/words \> $adir.JOB/words_text '&&' \
    join -j 1 $adir.JOB/{lm_cost,ac_cost} \| awk -v acwt=$acwt "{print \\\$1, (- \\\$2 - \\\$3 * acwt);}" \| \
    join -j 1 \- $adir.JOB/words_text \| awk "{\\\$1=substr(\\\$1, 1, match(\\\$1, /-[^-]*$/)-1)}1" \
    \> $nbest_dir/nbest/JOB/nbest.txt

# Note: nbest.txt is of this format:
# (uid, log-prob, sentence)
# In Kaldi, the "log-prob" can be positive, but it does not matter if we normalize the posterior for each sentence

# realpath $adir.$i/words_text
# less $adir.$i/words_text
# less /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_callhome_train_sw1_fsh_fg_rnnlm_1e_0.45/nbest/archives.40/words_text
# vi /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c//exp/chain/tdnn7r_sp/decode_callhome_train_sw1_fsh_fg_rnnlm_1e_0.45//nbest/archives.1/{acwt,lmwt,words_text} -O

for job_id in `seq 1 $nj`; do 
    cut -d' ' -f1 $nbest_dir/nbest/$job_id/nbest.txt | sort -u > $nbest_dir/nbest/$job_id/utt
    # wc -l $nbest_dir/temp/$job_id/utt
done

echo $nj > $nbest_dir/num_jobs

exit 0;


### local/exp-20210204.sh

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
fix_long_dur_script=/export/fs04/a12/rhuang/kws/kws/local/fix_long_dur.sh
data=std2006_dev
data=std2006_eval
data=callhome_train
data=callhome_dev
data=callhome_eval
montreal=
montreal=".montreal"
montreal=".ref"
scale=1.0
kaldi=
kaldi="_kaldi"
kaldi="_k2"
dev=
skip_optimization=true

# kaldi nbest kws:
kaldi_path=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
nbest_dir=${kaldi_path}/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/
indices_dir=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/kws_indices_kaldi/${data}_100/

score_type=_pos
for scale in 0.0 0.2 0.5 1.0; do
    echo `date` "scale=$scale"

    cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
    time bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 0 --score_type "_pos"

    time bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 1 --skip_optimization "$skip_optimization" --score_type "_pos"
    [[ -d $indices_dir/kws_indices_2_${scale}${montreal}_eps2 ]] && rm -r $indices_dir/kws_indices_2_${scale}${montreal}_eps2
    mv $indices_dir/kws_indices $indices_dir/kws_indices_2_${scale}${montreal}_eps2; echo $indices_dir/kws_indices_2_${scale}${montreal}_eps2
    ls -lah $indices_dir/kws_indices_2_${scale}${montreal}_eps2/index.1.gz
done

# Step 1. run normal kws: you can terminate the program after *.fsts are generated
cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3 --skip_kw_fst false --eps2_suffix ""
# Step 2. generate new *.fsts
fsts=data/${data}/kws/keywords.fsts
wc -l $fsts
mv $fsts ${fsts%.*}.original.fsts
wc -l ${fsts%.*}.original.fsts
# strange: it will only be succesful after the 2nd run
bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 2 --fst ${fsts%.*}.original.fsts
ln -sf $(realpath ${fsts%.*}.original.eps2.fsts) $fsts
# Step 3. run eps2 kws to get atwv/mtwv/otwv/stwv
bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3  --max_distance_range "25 50 500"

