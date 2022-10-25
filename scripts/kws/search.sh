#!/bin/bash
# Copyright (c) 2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

# INPUTS:
#   - lats_dir
#   - kws_data_dir
#   - indices_tag

lats_dir=
kws_data_dir=
indices_tag=""
cmd=run.pl
stage=

frame_subsampling_factor=3

max_states_scale=-1
max_states=1000000
skip_optimization=false
nbest=-1

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
log "------------------------------------------------"

indices_dir=$lats_dir/kws_indices${indices_tag}
log "The indices are save in: $indices_dir"

nj=`cat $indices_dir/num_jobs`
log nj: "$nj"

kwsoutput=$indices_dir/kws_results
mkdir -p $kwsoutput
log "The results will be save in: $kwsoutput"

filter_script="/export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet_gpu/bin/python /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/filter_kws_results.py"
# filter_script=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/local/kws/filter_kws_results.pl
# filter_script=/export/fs04/a12/rhuang/kaldi_latest/kaldi/egs/mini_librispeech/s5/local/kws/filter_kws_results.pl

if [[ ${stage} == 3 ]]; then
    log "Stage 3: Search"

    $cmd JOB=1:$nj $kwsoutput/log/search.JOB.log \
        set -e  -o pipefail '&&' \
        kws-search --strict=false --negative-tolerance=-1 \
            --frame-subsampling-factor=$frame_subsampling_factor \
            "ark:gzip -cdf $indices_dir/index.JOB.gz|" "ark:$kws_data_dir/keywords.eps2.fsts" \
            "ark,t:| sort -u | gzip -c > $kwsoutput/result.JOB.gz" \
            "ark,t:| sort -u | gzip -c > $kwsoutput/stats.JOB.gz" 

    log "Done: $kwsoutput/results"
fi

if [[ ${stage} == 4 ]]; then
    log "Stage 4: Post-processing"

    # This is a memory-efficient way how to do the filtration
    # we do this in this way because the result.* files can be fairly big
    # and we do not want to run into troubles with memory
    files=""
    for job in $(seq 1 $nj); do
      if [ -f $kwsoutput/result.${job}.gz ] ; then
       files="$files <(gunzip -c $kwsoutput/result.${job}.gz)"
      elif [ -f $kwsoutput/result.${job} ] ; then
       files="$files $kwsoutput/result.${job}"
      else
        echo >&2 "The file $kwsoutput/result.${job}[.gz] does not exist"
        exit 1
      fi
    done
    # we have to call it using eval as we need the bash to interpret
    # the (possible) command substitution in case of gz files
    # bash -c would probably work as well, but would spawn another
    # shell instance
    # eval "sort -m -u $files" |\
    #   local/kws/filter_kws_results.pl --likes --nbest $nbest > $kwsoutput/results || exit 1
    script=/export/fs04/a12/rhuang/kws/kws-release/scripts/kws/filter_kws_results.py
    eval "sort -m -u $files" |\
        $filter_script --likes --nbest $nbest > $kwsoutput/results || exit 1
    
    log "Done: $(wc -l $kwsoutput/results)"
fi





