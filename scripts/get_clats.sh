#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

# begin configuration section.
cmd=run.pl
scale=1.0
stage=0
stop_stage=10000
nj=
get_nbest=
max_states_scale=-1
max_states=1000000
skip_optimization=false
kaldi=
montreal=
score_type=
nsize=
#end configuration section.

# [ -f ./path.sh ] && . ./path.sh
[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/get_clats.sh [--cmd (run.pl|queue.pl...)] <nbest-dir> <data-dir> <indices-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --scale [float]                 # the scaling factor for nbest scores."
#   echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
#   echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  exit 1;
fi

nbest_dir=$1
data_dir=$2
indices_dir=$3

echo "------------------ Parameters ------------------"
echo nbest_dir: $nbest_dir
echo data_dir: $data_dir
echo indices_dir: $indices_dir
echo scale: $scale
echo kaldi: $kaldi
echo montreal: $montreal
echo score_type: $score_type
echo "------------------------------------------------"

# cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12

mkdir -p $indices_dir/temp
mkdir -p $indices_dir/log
[[ -z "$nj" ]] && [[ -d $nbest_dir/logdir ]] && nj=`ls -d1 $nbest_dir/logdir/output.* | wc -l`  # espnet
[[ -z "$nj" ]] && [[ -f $nbest_dir/num_jobs ]] && nj=`cat $nbest_dir/num_jobs`  # kaldi

if [[ -z "$nj" ]]; then
    find $nbest_dir/temp -maxdepth 1 -type d -regextype egrep -regex '.*/[0-9]+' | wc -l > $nbest_dir/num_jobs
    nj=`cat $nbest_dir/num_jobs`

    echo $nj > $indices_dir/num_jobs
fi

##############################
# Convert nbest to sausage
# This part replaces the above codes after using the rover.py script
##############################
if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    echo "Stage 0: Convert nbest to lattice"

    compressor=gzip
    # compressor=cat

    utt2dur=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/$(basename $data_dir)/utt2dur
    # utt2dur=$data_dir/utt2dur

    words=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt

    if [ -z $montreal ]; then
        ali=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/tri3_ali_1best${kaldi}_$(basename $data_dir)/1best.ali${montreal}.txt
    elif [ $montreal == ".montreal" ]; then
        ali=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/tri3_ali_1best${kaldi}_$(basename $data_dir)/1best.ali${montreal}.txt
    elif [ $montreal == ".ref" ]; then
        ali=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/tri3_ali_ref_$(basename $data_dir)/ref.ali.txt
    else
        echo "Cannot reach here!"
        exit 1;
    fi

    if [[ "$kaldi" == *"k2"* ]]; then
        ali=${nbest_dir}/1best.k2.ali.txt
    fi

    echo "Using aligment: $ali" 
    ls -lah $ali

    mkdir -p ${indices_dir}

    script=/export/fs04/a12/rhuang/kws/kws/local/rover5.py
    $cmd JOB=1:$nj ${indices_dir}/log/nbest2lat.JOB.log \
        mkdir -p ${indices_dir}/temp/JOB/ '&&' \
        /export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet_gpu/bin/python3 \
          $script --workdir ${nbest_dir}/temp/JOB/ \
          --score_type $score_type \
          --dur $utt2dur \
          --words $words \
          --ali $ali \
          --dur $utt2dur \
          --scale $scale \
          --nsize $nsize \| \
         $compressor \> ${indices_dir}/temp/JOB/clat.scale${scale}${montreal}${score_type}.gz || exit 1; 

    grep -iF "error" ${indices_dir}/log/nbest2lat.*.log
    echo "Done: ${indices_dir}/temp/1/clat.scale${scale}${montreal}${score_type}.gz"
fi
