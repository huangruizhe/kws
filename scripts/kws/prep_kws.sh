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

