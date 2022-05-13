#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

# First, we need to use MFA to align the 1st best hypo
# with local/run_montreal.sh

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
mv data/montreal data/montreal_for_espnet_wer11.9
mkdir data/montreal

# for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
# done

data=std2006_dev
kaldi=   # "_kaldi"
espnet_path=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
indices_dir=${espnet_path}/kws_indices${kaldi}/${data}_100/
mfa=data/montreal/${data}
mkdir -p $mfa

# Just go to local/run_montreal.sh and follow the steps there

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
mkdir data/montreal

# for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
# done

data=std2006_dev
kaldi=   # "_kaldi"
espnet_path=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
indices_dir=${espnet_path}/kws_indices${kaldi}/${data}_100/
mfa=data/montreal/${data}
mkdir -p $mfa

for f in ${indices_dir}/temp/*/nbest.txt; do
    python3 /export/fs04/a12/rhuang/kws/kws/local/get_one_best.py \
        --nbest $f --mfa $mfa
done

# example running
for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
    echo $data
    # kaldi=   # "_kaldi"
    kaldi="_kaldi"   # "_kaldi"
    espnet_path=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
    indices_dir=${espnet_path}/kws_indices${kaldi}/${data}_100/
    mfa=data/montreal/${data}${kaldi}
    mkdir -p $mfa

    for f in ${indices_dir}/temp/*/nbest.txt; do
        python3 /export/fs04/a12/rhuang/kws/kws/local/get_one_best.py \
            --nbest $f --mfa $mfa
    done    
done


pip install --user kaldiio

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c 
. ./path.sh

for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
    echo $data

    wavdir=data/montreal/${data}_wav
    logdir=$wavdir/log
    mkdir -p $logdir

    # while IFS= read -r line; do
    #     echo "Text read from file: $line"
    # done < $segments

    scp=data/${data}/wav.scp
    segments=data/${data}/segments
    nj=40

    split_segments=
    for n in $(seq $nj); do
        split_segments="$split_segments $logdir/segments.$n"
    done
    utils/split_scp.pl $segments $split_segments

    script=/export/fs04/a12/rhuang/kws/kws/local/ark2wav.py
    queue.pl JOB=1:$nj $logdir/get_wav.JOB.log \
        extract-segments scp,p:$scp $logdir/segments.JOB ark:"| gzip -c > $logdir/temp.JOB.ark.gz" '&&' \
        /export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet/bin/python3 \
        $script --ark $logdir/temp.JOB.ark.gz --out $wavdir
    
    rm $logdir/temp.*.ark.gz
done

# example
# scp=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/callhome_dev/wav.scp
# segments=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/test/segments
# # line="fsh_60262_exA_A_005670_007520 fsh_60262_exA_A 5.670 7.520"
# # extract-segments scp,p:$scp <(echo $line) ark:"| gzip -c > a.ark.gz"
# extract-segments scp,p:$scp $segments ark:"| gzip -c > a.ark.gz"
# python3 /export/fs04/a12/rhuang/kws/kws/local/ark2wav.py a.ark.gz .

# Very slow. Can we speed this up?
for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
    echo $data ====== `date`

    wavdir=data/montreal/${data}_wav
    mfa1=data/montreal/${data}
    mfa2=data/montreal/${data}_kaldi

    for f in $wavdir/*.wav; do
        bname=$(basename $f)
        fname=${bname%.*}

        [ -e $mfa1/$fname.wav ] && rm $mfa1/$fname.wav
        [ -e $mfa2/$fname.wav ] && rm $mfa2/$fname.wav

        if [ -f "$mfa1/$fname.txt" ]; then
            ln -s $(realpath $f) $mfa1/.
        else
            echo "$mfa1": no txt file "for" $f
        fi

        if [ -f "$mfa2/$fname.txt" ]; then
            ln -s $(realpath $f) $mfa2/.
        else
            echo "$mfa2": no txt file "for" $f
        fi
    done
done


for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
    echo $data ====== `date`

    wavdir=data/montreal/${data}_wav
    mfa1=data/montreal/${data}
    mfa2=data/montreal/${data}_kaldi

    for f in $mfa1/*.txt; do
        mv -- "$f" "${f%.txt}.lab"
    done

    for f in $mfa2/*.txt; do
        mv -- "$f" "${f%.txt}.lab"
    done
done


for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
    echo $data ====== `date`

    mfa1=data/montreal/${data}
    mfa2=data/montreal/${data}_kaldi
    
    echo "mfa1"
    # ls -1 $mfa1/*.lab | wc -l   # -bash: /bin/ls: Argument list too long
    # ls -1 $mfa1/*.wav | wc -l
    find $mfa1 -name '*.lab' | wc -l
    find $mfa1 -name '*.wav' | wc -l

    echo "mfa2"
    # ls -1 $mfa2/*.lab | wc -l
    # ls -1 $mfa2/*.wav | wc -l
    find $mfa2 -name '*.lab' | wc -l
    find $mfa2 -name '*.wav' | wc -l
done


cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
conda activate aligner
for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
    echo $data ====== `date`

    mfa1=data/montreal/${data}
    mfa2=data/montreal/${data}_kaldi

    nj=50
    cmd=queue.pl
    # time mfa align -j $nj $mfa1 english english ${mfa1}_aligned
    # time mfa align -j $nj $mfa2 english english ${mfa2}_aligned
    $cmd JOB=1:1 $mfa1/mfa.JOB.log \
        conda activate aligner '&&' \
        mfa align -j $nj --clean $mfa1 english english ${mfa1}_aligned &    # This command cannot be run in parallel across datasets; it has to be run one-by-one

    $cmd JOB=1:1 $mfa2/mfa.JOB.log \
        conda activate aligner '&&' \
        mfa align -j $nj --clean $mfa2 english english ${mfa2}_aligned &
done

# cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
# test=data/montreal/test
# mfa align $test english english ${test}_aligned
# ls ${test}_aligned

for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
    echo $data ====== `date`

    mfa1=data/montreal/${data}
    mfa2=data/montreal/${data}_kaldi
    
    echo "mfa1"
    find ${mfa1}_aligned -name '*.TextGrid' | wc -l

    echo "mfa2"
    find ${mfa2}_aligned -name '*.TextGrid' | wc -l
done


### convert the textgrid files to kaldi's ali files
for data in std2006_dev std2006_eval callhome_dev callhome_eval callhome_train; do
    echo $data ====== `date`

    mfa1=data/montreal/${data}
    mfa2=data/montreal/${data}_kaldi
    
    words=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt
    script=/export/fs04/a12/rhuang/kws/kws/local/textgrid2ali.py

    dir=exp/tri3_ali_1best_$data
    echo $dir
    echo $dir/1best.ali.montreal.txt
    /export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet/bin/python3 \
      $script --ali-dir ${mfa1}_aligned --words $words > $dir/1best.ali.montreal.txt

    dir=exp/tri3_ali_1best_kaldi_$data
    echo $dir
    echo $dir/1best.ali.montreal.txt
    /export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet/bin/python3 \
      $script --ali-dir ${mfa2}_aligned --words $words > $dir/1best.ali.montreal.txt
done
