#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

# cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
# fix_long_dur_script=/export/fs04/a12/rhuang/kws/kws/local/fix_long_dur.sh
# data=std2006_dev
# data=std2006_eval
# data=callhome_train
# data=callhome_dev
# data=callhome_eval
# montreal=
# montreal=".montreal"
# montreal=".ref"
# scale=1.0
# kaldi=
# kaldi="_kaldi"
########################################
# espnet nbest kws:
# espnet_path=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
# nbest_dir=${espnet_path}/exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
# indices_dir=${espnet_path}/kws_indices/${data}_100/
########################################
# kaldi nbest kws:
# kaldi_path=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
# nbest_dir=${kaldi_path}/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/
# indices_dir=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices_kaldi/${data}_100/
########################################
# bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 0
#
# bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 1
# [[ -d $indices_dir/kws_indices_2_${scale}${montreal}_eps2 ]] && rm -r $indices_dir/kws_indices_2_${scale}${montreal}_eps2
# mv $indices_dir/kws_indices $indices_dir/kws_indices_2_${scale}${montreal}_eps2; echo $indices_dir/kws_indices_2_${scale}${montreal}_eps2
#
# # Step 1. run normal kws
# bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3 --skip_kw_fst false --eps2_suffix ""
# # Step 2. generate new *.fsts
# fsts=data/${data}/kws/keywords.fsts
# wc -l $fsts
# mv $fsts ${fsts%.*}.original.fsts
# wc -l ${fsts%.*}.original.fsts
# bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 2 --fst ${fsts%.*}.original.fsts
# ln -sf $(realpath ${fsts%.*}.original.eps2.fsts) $fsts
# # Step 3. run eps2 kws
# bash $fix_long_dur_script --kaldi "$kaldi" --data $data --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 3
#
# bash $fix_long_dur_script --kaldi "$kaldi" --data std2006_eval --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 4 --dev std2006_dev
# bash $fix_long_dur_script --kaldi "$kaldi" --data callhome_eval --nbest-dir $nbest_dir --indices_dir $indices_dir --scale $scale --montreal "$montreal" --stage 4 --dev callhome_dev

data=
nbest_dir=
indices_dir=
scale=
montreal=
stage=
fst=
kaldi=
skip_kw_fst=true
eps2_suffix=_eps2

max_states_scale=-1
max_states=1000000
skip_optimization=false
dev=

create_catetories=false

max_distance=50
max_distance_range="25 50 100 500"

sweep_step=0.005

score_type=

cmd=queue.pl

[ -f ./path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

echo "------------------ Parameters ------------------"
echo nbest_dir: $nbest_dir
echo data: $data
echo indices_dir: $indices_dir
echo scale: $scale
echo kaldi: $kaldi
echo montreal: $montreal
echo "------------------------------------------------"

[[ -z "$nj" ]] && [[ -d $nbest_dir/logdir ]] && nj=`ls -d1 $nbest_dir/logdir/output.* | wc -l`  # espnet
[[ -z "$nj" ]] && [[ -f $nbest_dir/num_jobs ]] && nj=`cat $nbest_dir/num_jobs`  # kaldi

echo nj: "$nj"

if [[ ${stage} == 0 ]]; then
    echo "Converting <eps> to <eps2> in clat..."

    $cmd JOB=1:$nj $indices_dir/log/temp.JOB.log \
        set -e -o pipefail '&&' \
        zcat $indices_dir/temp/JOB/clat.scale$scale${montreal}${score_type}.gz \| \
        awk "BEGIN{FS=OFS=\" \";}{if (\$3 == \"<eps>\") \$3=\"<eps2>\"; print};" \| \
        python3 /export/fs04/a12/rhuang/kws/kws/local/eps2.py \| \
        gzip \> $indices_dir/temp/JOB/clat.scale$scale${montreal}${score_type}.eps2.gz
    
    echo Done: $indices_dir/temp/1/clat.scale$scale${montreal}${score_type}.eps2.gz

    words=$indices_dir/words.eps2.txt
    cp /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt $words
    grep -q "<eps2>" $words || echo "<eps2>" $(wc -l $words | cut -d' ' -f1) >> $words
fi

if [[ ${stage} == 1 ]]; then
    echo "Stage 1: Build Kaldi's KWS index over the lattices"

    utter_id=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/${data}/kws/utt.map
    words=$indices_dir/words.eps2.txt
    
    mkdir -p $indices_dir/kws_indices

    # echo $indices_dir/temp/JOB/clat.scale$scale${montreal}.eps2.gz

    # verbose="--verbose=1"
    $cmd JOB=1:$nj $indices_dir/log/kws_index.JOB.log \
        set -e -o pipefail '&&' \
        zcat $indices_dir/temp/JOB/clat.scale$scale${montreal}${score_type}.eps2.gz \| \
            utils/sym2int.pl --map-oov \\\<unk\\\> -f 3 $words \| \
            lattice-determinize ark:- ark:- \| \
            lattice-to-kws-index --max-states-scale=${max_states_scale} --allow-partial=true \
              --frame-subsampling-factor=3 $verbose \
              --max-silence-frames=50 --strict=true ark:$utter_id ark,t:- ark:- \| \
            kws-index-union --skip-optimization=${skip_optimization} --strict=true --max-states=${max_states} \
              ark:- "ark:$indices_dir/kws_indices/index.JOB.gz"
            # ark:- "ark,t:$indices_dir/kws_indices/index.JOB.txt"
            # ark:- "ark:$indices_dir/kws_indices/index.JOB.gz"
    
    touch $indices_dir/kws_indices/.done.index
    echo $nj > $indices_dir/kws_indices/num_jobs
    echo "Done:" $(realpath $indices_dir/kws_indices)

    # mv $indices_dir/kws_indices $indices_dir/kws_indices_2_${scale}${montreal}_eps2
fi

if [[ ${stage} == 2 ]]; then
    echo "Stage 2: Convert *.fsts to *.eps2.fsts for the keywords"

    script=/export/fs04/a12/rhuang/kws/kws/local/fix_long_dur_fst.py
    words=$indices_dir/words.eps2.txt

    python3 /export/fs04/a12/rhuang/kws/kws/local/fix_long_dur_fst.py \
      --fst $fst \
      --eps2 `grep "<eps2>" $words | cut -d' ' -f2` \
      > ${fst%.*}.eps2.fsts
    
    wc -l $fst ${fst%.*}.eps2.fsts
    echo Done: ${fst%.*}.eps2.fsts
fi 

if [[ ${stage} == 3 ]]; then
    echo "Stage 3: KWS with eps2"

    cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c

    if [[ $data == "std2006_dev" || $data == "std2006_eval" ]]; then
        keywords=/export/fs04/a12/rhuang/kws/kws/data0/${data}/kws/keywords.${data}.txt  # NIST
        # keywords=/export/fs04/a12/rhuang/kws/kws/data0/${data}/kws/queries/keywords.txt
    elif [[ $data == "callhome_train" || $data == "callhome_dev" || $data == "callhome_eval" ]]; then
        keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt
    fi

    # kws_indices_dir=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices${kaldi}/${data}_100/kws_indices
    kws_indices_dir=$indices_dir/kws_indices
    expid=2
    # scale=1.0
    start_stage=0  # start_stage=5 for scoring only
    system=exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/
    rm ${kws_indices_dir}_${expid}
    ln -sf ${kws_indices_dir}_${expid}_${scale}${montreal}${score_type}${eps2_suffix}  ${kws_indices_dir}_${expid}
    ls -lah ${kws_indices_dir}_${expid}
    time bash local/kws/run_kws_std2006.nbest.sh \
        --max-distance $max_distance --keywords $keywords --expid $expid \
        --stage $start_stage --data data/${data} --output data/${data}/kws/ \
        --create_catetories $create_catetories \
        --skip_kw_fst "$skip_kw_fst" --skip_search "true" \
        --indices_dir ${kws_indices_dir} \
        --system $system
    
    expid=2
    start_stage=5
    for max_distance in $max_distance_range; do
        [[ -L "$file" && -d "$file" ]] && rm ${system}/kws_$expid

        time bash local/kws/run_kws_std2006.nbest.sh \
            --max-distance $max_distance --keywords $keywords --expid $expid \
            --stage $start_stage --data data/${data} --output data/${data}/kws/ \
            --create_catetories $create_catetories \
            --skip_kw_fst "$skip_kw_fst" \
            --indices_dir ${kws_indices_dir} \
            --sweep_step ${sweep_step} \
            --system $system
        
        f=$system/kws_$expid/details/score.txt
        echo $f
        echo max_distance=$max_distance ntrue_raw=$(cat $system/kws_$expid/details/ntrue_raw)
        readarray -t results < <(cat $f | rev | cut -d' ' -f1 | rev); echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}

        # print_all_metrics_and_ntrue $system $expid
        # find_best_ntrue $system $expid

        new_dir=${system}/kws_${expid}_${max_distance}${kaldi}${montreal}${score_type}${eps2_suffix}
        [[ -d ${new_dir} ]] && rm -r ${new_dir}
        mv ${system}/kws_$expid ${new_dir}
        echo mv ${system}/kws_$expid ${new_dir}
    done
fi

if [[ ${stage} == 4 ]]; then
    echo "Stage 4: KWS with eps2 -- use the optimal ntrue value on dev for eval"

    cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c

    eval=$data

    max_distance=50
    if [[ $data == "std2006_dev" || $data == "std2006_eval" ]]; then
        keywords=/export/fs04/a12/rhuang/kws/kws/data0/${data}/kws/keywords.${data}.txt  # NIST
        # keywords=/export/fs04/a12/rhuang/kws/kws/data0/${data}/kws/queries/keywords.txt
    elif [[ $data == "callhome_train" || $data == "callhome_dev" || $data == "callhome_eval" ]]; then
        keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt
    fi

    kws_indices_dir=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices${kaldi}/${data}_100/kws_indices
    expid=2
    scale=1.0
    start_stage=0  # start_stage=5 for scoring only
    system=exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/
    rm ${kws_indices_dir}_${expid}
    ln -sf ${kws_indices_dir}_${expid}_${scale}${montreal}${eps2_suffix}  ${kws_indices_dir}_${expid}
    ls -lah ${kws_indices_dir}_${expid}

    # run this first to generate the search results
    time bash local/kws/run_kws_std2006.nbest.sh \
        --max-distance $max_distance --keywords $keywords --expid $expid \
        --stage $start_stage --data data/${data} --output data/${data}/kws/ \
        --create_catetories $create_catetories \
        --skip_kw_fst "false" --skip_search "false" \
        --indices_dir ${kws_indices_dir} \
        --system $system
    
    system_dev=exp/chain/tdnn7r_sp/decode_${dev}_sw1_fsh_fg_rnnlm_1e_0.45/
    system_eval=exp/chain/tdnn7r_sp/decode_${eval}_sw1_fsh_fg_rnnlm_1e_0.45/

    for max_distance in 25 50 500; do
        echo "----max_distance = $max_distance----"

        rm -rf ${system_dev}/kws_${expid}
        ln -sf $(realpath ${system_dev}/kws_${expid}_${max_distance}${montreal}${eps2_suffix}) $system_dev/kws_${expid}
        ls -lah ${system_dev}/kws_${expid}

        f=${system_dev}/kws_${expid}/details/score.txt
        realpath $f
        echo max_distance=$max_distance
        readarray -t results < <(cat $f | rev | cut -d' ' -f1 | rev); echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}

        # print_all_metrics_and_ntrue $system_dev $expid
        # find_best_ntrue $system_dev $expid

        echo "----eval----"
        echo "Using ntrue from:" $(realpath ${system_dev}/kws_${expid})
        rm -rf ${system_eval}/kws_${expid}
        ln -s $(realpath ${system_eval}/kws_${expid}_${max_distance}${montreal}${eps2_suffix}) ${system_eval}/kws_${expid}
        time bash local/kws/score_nbest.sh  --cmd run.pl --min-lmwt $expid --max-lmwt $expid \
            --max_distance ${max_distance} \
            --ntrue_from ${system_dev}/kws \
            data/lang data/${eval} ${system_eval}/kws
        
        f=${system_eval}/kws_${expid}/details/score.txt
        readlink -f $f
        echo max_distance=$max_distance "eval"
        readarray -t results < <(cat $f | rev | cut -d' ' -f1 | rev); echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}
    done

fi