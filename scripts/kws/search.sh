#!/bin/bash
# Copyright (c) 2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

# INPUTS:
#   - lats_dir
#   - kws_data_dir
#   - indices_tag
#   - kwlist

lats_dir=
kws_data_dir=
indices_tag=""
kwlist=
cmd=run.pl
stage=

max_states_scale=-1
max_states=1000000
skip_optimization=false

[ -f ./path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

log "------------------ Parameters ------------------"
log lats_dir: $lats_dir
log kws_data_dir: $kws_data_dir
log indices_tag: $indices_tag
log stage: $stage
log kwlist: $kwlist
log "------------------------------------------------"

indices_dir=$lats_dir/kws_indices${indices_tag}
log "The indices are save in: $indices_dir"

nj=`cat $indices_dir/num_jobs`
log nj: "$nj"

output=$indices_dir/kws_results
mkdir -p $output
log "The results will be save in: $output"

if [[ ${stage} == 2 ]]; then
    echo "Stage 2: Generate *.eps2.fsts for the keywords"
    
    words=$lats_dir/words.eps2.txt

    [[ -z $kwlist ]] && kwlist=$kws_data_dir/keywords.txt
    log Using keywords: $kwlist
    cp $kwlist $output/keywords.txt

    oov_id=`grep "<unk>" $words | awk '{print $2}'`
    # TODO: oov_id=0 in the original script
    cat $kwlist | \
        local/kws/keywords_to_indices.pl --map-oov $oov_id $words | \
        sort -u > $output/keywords.int
    
    # generate keywords.fsts
    local/kws/compile_keywords.sh $output $(dir $words) $output/tmp.2
    cp $output/tmp.2/keywords.fsts $output/keywords.fsts

    # convert keywords.fsts to keywords.eps2.fsts
    script=/export/fs04/a12/rhuang/kws/kws-release/scripts/kws_py/add_esp2_to_fsts.py
    python3 $script \
      --fsts $output/keywords.fsts \
      --eps2 `grep "<eps2>" $words | awk '{print $2}'` \
      > $output/keywords.eps2.fsts
    
    wc -l $output/keywords.fsts $output/keywords.eps2.fsts
    log "Done: $output/keywords.eps2.fsts"
fi 

if [[ ${stage} == 3 ]]; then
    echo "Stage 3: KWS with eps2"

    cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c

    if [[ $data == "std2006_dev" || $data == "std2006_eval" ]]; then
        keywords=/export/fs04/a12/rhuang/kws/kws/data0/${data}/kws/keywords.${data}.txt  # NIST
        # keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt
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

        new_dir=${system}/kws_${expid}_${max_distance}${kaldi}${montreal}${score_type}_${scale}${eps2_suffix}
        [[ -d ${new_dir} ]] && rm -r ${new_dir}
        mv ${system}/kws_$expid ${new_dir}
        echo mv ${system}/kws_$expid ${new_dir}
        realpath ${new_dir}
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




