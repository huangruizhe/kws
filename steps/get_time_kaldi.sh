#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
data=std2006_dev

# espnet nbest kws:
espnet_path=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
nbest_dir=${espnet_path}/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
indices_dir=${espnet_path}/kws_indices${kaldi}/${data}_100/
script=/export/fs04/a12/rhuang/kws/kws/local/alignment.sh
time bash $script --cmd queue.pl --stage 0 --stop_stage 0 $data $nbest_dir $indices_dir
time bash $script --cmd queue.pl --stage 1 $data $nbest_dir $indices_dir

# /export/fs04/a12/rhuang/kws/kws/local/alignment.sh

cmd=run.pl
lang=data/lang
stage=0
stop_stage=10000
nj=
kaldi=

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/alignment.sh [--cmd (run.pl|queue.pl...)] <data> <nbest-dir> <indices-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  exit 1;
fi

data=$1
nbest_dir=$2
indices_dir=$3

data_dir=data/${data}
[[ -z "$nj" ]] && [[ -d $nbest_dir/logdir ]] && nj=`ls -d1 $nbest_dir/logdir/output.* | wc -l`  # espnet
[[ -z "$nj" ]] && [[ -f $nbest_dir/num_jobs ]] && nj=`cat $nbest_dir/num_jobs`  # kaldi


echo "------------------ Parameters ------------------"
echo data_dir: $data_dir
echo nbest_dir: $nbest_dir
echo indices_dir: $indices_dir
echo nj: $nj
echo "------------------------------------------------"

mkdir -p $indices_dir/temp
mkdir -p $indices_dir/log


if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    echo "Stage 0: get 1st best"

    script=/export/fs04/a12/rhuang/kws/kws/local/get_one_best.py
    $cmd JOB=1:$nj ${indices_dir}/log/get1best.JOB.log \
        set -e -o pipefail '&&' \
        python3 $script --nbest ${indices_dir}/temp/JOB/nbest.txt \
        \> ${indices_dir}/temp/JOB/1best.txt || exit 1; 
    
    grep -iF "error" ${indices_dir}/log/get1best.*.log

    utils/copy_data_dir.sh data/$data data/${data}_1best${kaldi}
    cat ${indices_dir}/temp/*/1best.txt | sed '/^$/d' | sort -s -k 1,1 > data/${data}_1best${kaldi}/text

    utils/validate_data_dir.sh data/${data}_1best${kaldi}
    utils/fix_data_dir.sh data/${data}_1best${kaldi}

    # Why this is needed? Otherwise it seems there will be error in stage 1
    split_data.sh data/${data}_1best${kaldi} $nj
fi


if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    echo "Stage 1: Create alignment exp/tri3_ali_1best${kaldi}_$data"
    # steps/align_fmllr.sh --nj $nj --cmd "$cmd" \
    #     data/${data}_1best $lang exp/tri3 exp/tri3_ali_1best_$data
    steps/align_fmllr.sh --nj $nj --cmd "$cmd" \
        data/${data}_1best${kaldi} $lang exp/tri3 exp/tri3_ali_1best${kaldi}_$data
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    echo "Stage 2: Get word alignment"

    if [ ! -f $lang/L_align.fst ]; then
        echo "$0: generating $lang/L_align.fst"
        lang_tmp=data/local/lang_tmp
        local/kws/make_L_align.sh $lang_tmp $lang $lang 2>&1 | tee ${indices_dir}/log/L_align.log
    fi

    oov=`cat $lang/oov.txt`
    wbegin=`grep "#1" $lang/phones.txt | head -1 | awk '{print $2}'`
    wend=`grep "#2" $lang/phones.txt | head -1 | awk '{print $2}'`

    dir=exp/tri3_ali_1best${kaldi}_$data
    run.pl ${indices_dir}/log/ali_word.log \
        set -e -o pipefail '&&' \
        ali-to-phones $dir/final.mdl "ark:gunzip -c $dir/ali.*.gz|" ark,t:- \| \
        phones-to-prons $lang/L_align.fst $wbegin $wend ark:- "ark,s:utils/sym2int.pl -f 2- --map-oov '$oov' $lang/words.txt <data/${data}_1best${kaldi}/text|" ark,t:- \| \
        prons-to-wordali ark:- "ark:ali-to-phones --write-lengths=true $dir/final.mdl 'ark:gunzip -c $dir/ali.*.gz|' ark,t:- |" ark,t:- \
        \> ${dir}/1best.ali.txt
    
    echo "Done: ${dir}/1best.ali.txt"
fi


