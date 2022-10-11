#!/bin/bash
# Copyright (c) 2022, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

stage=0
cmd=run.pl
data=std2006_dev 
keywords=/export/fs04/a12/rhuang/kws/kws/data0/std2006_dev/kws/keywords.std2006_dev.txt 
create_catetories="true" 
flen=0.01
kws_data_dir=

data_dir=data/$data
lang=data/lang

. ./utils/parse_options.sh
. ./path.sh

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

[[ -z "$kws_data_dir" ]] && kws_data_dir=data/$data/kws/

mkdir -p $kws_data_dir
if [ $stage -le 1 ] ; then
  ## generate the auxiliary data files
  ## utt.map
  ## wav.map
  ## trials
  ## frame_length
  ## keywords.int

  ## For simplicity, we do not generate the following files
  ## categories

  ## We will generate the following files later
  ## hitlist
  ## keywords.fsts

  [ ! -f $data_dir/utt2dur ] &&
    utils/data/get_utt2dur.sh $data_dir

  duration=$(cat $data_dir/utt2dur | awk '{sum += $2} END{print sum}' )

  echo $duration > $kws_data_dir/trials
  echo $flen > $kws_data_dir/frame_length

  echo "Number of trials: $(cat $kws_data_dir/trials)"
  echo "Frame lengths: $(cat $kws_data_dir/frame_length)"

  echo "Generating map files"
  cat $data_dir/utt2dur | awk 'BEGIN{i=1}; {print $1, i; i+=1;}' > $kws_data_dir/utt.map
  cat $data_dir/wav.scp | awk 'BEGIN{i=1}; {print $1, i; i+=1;}' > $kws_data_dir/wav.map

  cp $lang/words.txt $kws_data_dir/words.txt
  cp $keywords $kws_data_dir/keywords.txt
  map_oov=`awk 'BEGIN{a=0}{if ($2>0+a) a=$2} END{print a+10000}' $kws_data_dir/words.txt`
  cat $kws_data_dir/keywords.txt | \
    local/kws/keywords_to_indices.pl --map-oov $map_oov  $kws_data_dir/words.txt | \
    sort -u > $kws_data_dir/keywords.int
  echo "# of keyword queries: $(wc -l $kws_data_dir/keywords.txt | awk '{print $1}')"

  cat $kws_data_dir/keywords.txt | \
    local/kws/keywords_to_oov.pl --map-oov $map_oov  $kws_data_dir/words.txt | \
    sort -u > $kws_data_dir/keywords.oovs

  # https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5d/local/kws_setup.sh
  if [[ $create_catetories == "true" ]]; then 
    cat $kws_data_dir/keywords.txt | local/search/create_categories.pl | local/search/normalize_categories.pl > $kws_data_dir/categories
  elif [[ -f $kws_data_dir/categories ]]; then
    mv $kws_data_dir/categories $kws_data_dir/categories.backup
  fi

  # convert the transcripts to lower cases
  # file=data/eval2000/text
  # paste <(cut -d' ' -f1 $file) <(cut -d' ' -f2- $file | tr '[:upper:]' '[:lower:]') > temp.txt
  # mv temp.txt $file
fi

if [ $stage -le 2 ] ; then
  ## this step generates the file hitlist

  ## in many cases, when the reference hits are given, the followin two steps \
  ## are not needed
  ## we create the alignments of the data directory
  ## this is only so that we can obtain the hitlist
  # steps/align_fmllr.sh --nj 5 --cmd "$cmd" \
  #    $data_dir $lang exp/tri3 exp/tri3b_ali_$data

  local/kws/create_hitlist.sh $data_dir $lang data/local/lang \
    exp/tri3b_ali_$data $kws_data_dir
fi

if [ $stage -le 3 ] ; then
    echo "Stage 3: Generate *.eps2.fsts for the keywords"
    
    words=$kws_data_dir/words.eps2.txt
    cp $kws_data_dir/words.txt $words
    grep -q "<eps2>" $words || echo "<eps2>" $(wc -l $words | cut -d' ' -f1) >> $words

    [[ -z $keywords ]] && keywords=$kws_data_dir/keywords.txt
    log Using keywords: `wc -l $keywords`

    # oov_id=`grep "<unk>" $words | awk '{print $2}'`
    # # TODO: oov_id=0 in the original script
    # cat $keywords | \
    #     local/kws/keywords_to_indices.pl --map-oov $oov_id $words | \
    #     sort -u > $kwsoutput/keywords.int
    
    # generate keywords.fsts
    local/kws/compile_keywords.sh $kws_data_dir $(dir $words) $kws_data_dir/tmp.2
    cp $kws_data_dir/tmp.2/keywords.fsts $kws_data_dir/keywords.fsts

    # convert keywords.fsts to keywords.eps2.fsts
    script=/export/fs04/a12/rhuang/kws/kws-release/scripts/kws_py/add_esp2_to_fsts.py
    python3 $script \
      --fsts $kws_data_dir/keywords.fsts \
      --eps2 `grep "<eps2>" $words | awk '{print $2}'` \
      > $kws_data_dir/keywords.eps2.fsts
    
    wc -l $kws_data_dir/keywords.fsts $kws_data_dir/keywords.eps2.fsts
    log "Done: $kws_data_dir/keywords.eps2.fsts"
fi 