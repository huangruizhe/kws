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
cmd=queue.pl
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
log "------------------------------------------------"

# [[ -z "$nj" ]] && [[ -d $nbest_dir/logdir ]] && nj=`ls -d1 $nbest_dir/logdir/output.* | wc -l`  # espnet
# [[ -z "$nj" ]] && [[ -f $nbest_dir/num_jobs ]] && nj=`cat $nbest_dir/num_jobs`  # kaldi

[[ -f $lats_dir/num_jobs ]] && nj=`cat $lats_dir/num_jobs`
[[ -z "$nj" ]] && nj=`ls -d1 $lats_dir/clat.*.gz | wc -l`

log nj: "$nj"


if [[ ${stage} == 0 ]]; then
    log "Converting <eps> to <eps2> in clat..."

    if [[ ! -d $lats_dir/clat_backup ]]; then
        mkdir $lats_dir/clat_backup
        mv $lats_dir/clat.*.gz $lats_dir/clat_backup/.
    fi

    $cmd JOB=1:$nj $lats_dir/log/convert_eps2.JOB.log \
        set -e -o pipefail '&&' \
        zcat $lats_dir/clat_backup/clat.JOB.gz \| \
        awk "BEGIN{FS=OFS=\" \";}{if (\$3 == \"<eps>\") \$3=\"<eps2>\"; print};" \| \
        gzip \> $lats_dir/clat.JOB.eps2.gz
    
    log Done: `ls -lah $lats_dir/clat.1.eps2.gz`

    words=$lats_dir/words.eps2.txt
    cp $kws_data_dir/words.txt $words
    grep -q "<eps2>" $words || echo "<eps2>" $(wc -l $words | cut -d' ' -f1) >> $words
fi

if [[ ${stage} == 1 ]]; then
    log "Stage 1: Build Kaldi's KWS index over the lattices"

    utter_id=$kws_data_dir/utt.map
    words=$lats_dir/words.eps2.txt
    
    indices_dir=$lats_dir/kws_indices${indices_tag}
    mkdir -p $indices_dir

    # verbose="--verbose=1"
    $cmd JOB=1:$nj $indices_dir/log/kws_index.JOB.log \
        set -e -o pipefail '&&' \
        zcat $lats_dir/clat.JOB.eps2.gz \| \
            utils/sym2int.pl --map-oov \\\<unk\\\> -f 3 $words \| \
            lattice-determinize ark:- ark:- \| \
            lattice-to-kws-index --max-states-scale=${max_states_scale} --allow-partial=true \
              --frame-subsampling-factor=3 $verbose \
              --max-silence-frames=50 --strict=true ark:$utter_id ark,t:- ark:- \| \
            kws-index-union --skip-optimization=${skip_optimization} --strict=true --max-states=${max_states} \
              ark:- "ark:$indices_dir/index.JOB.gz"
            # ark:- "ark,t:$indices_dir/index.JOB.txt"
    
    # grep error $indices_dir/log/kws_index.*.log

    touch $indices_dir/.done.index
    echo $nj > $indices_dir/num_jobs
    log "Done:" $(realpath $indices_dir)

    # mv $indices_dir/kws_indices $indices_dir/kws_indices_2_${scale}${montreal}_eps2
fi



# cd /export/fs04/a12/rhuang/kws/kws-release$

# indices_dir=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices_kaldi/std2006_dev_100/
# for i in `seq 1 50`; do
#     cp $indices_dir/temp/1/clat.scale1.0.gz test/clat.$i.gz
# done

# cp /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/kws/{words.txt,utt.map} test/kws_data_dir/.

# bash /export/fs04/a12/rhuang/kws/kws-release/scripts/kws/build_index.sh \
#  --lats_dir /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir \
#  --kws_data_dir /export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir \
#  --stage 1
