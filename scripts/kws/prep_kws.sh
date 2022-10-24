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

kaldi_path=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
lang=${kaldi_path}/data/lang

. ./utils/parse_options.sh
. ./path.sh

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

data_dir=${kaldi_path}/data/$data
[[ -z "$kws_data_dir" ]] && kws_data_dir=data/$data/kws/

echo "------------------ Parameters ------------------"
echo data: $data
echo keywords: $keywords
echo kws_data_dir: $kws_data_dir
echo create_catetories: $create_catetories
echo data_dir: $data_dir
echo "------------------------------------------------"

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
  cp $data_dir/utt2dur $kws_data_dir/utt2dur

  duration=$(cat $data_dir/utt2dur | awk '{sum += $2} END{print sum}' )

  echo $duration > $kws_data_dir/trials
  echo $flen > $kws_data_dir/frame_length

  echo "Number of trials: $(cat $kws_data_dir/trials)"
  echo "Frame lengths: $(cat $kws_data_dir/frame_length)"

  echo "Generating map files"
  cat $data_dir/utt2dur | awk 'BEGIN{i=1}; {print $1, i; i+=1;}' > $kws_data_dir/utt.map
  cat $data_dir/wav.scp | awk 'BEGIN{i=1}; {print $1, i; i+=1;}' > $kws_data_dir/wav.map

  cp $lang/words.txt $kws_data_dir/words.txt
  # add new words to ensure the hitlist contain these words!
  cat <(awk '{$1=""}1' $keywords | tr ' ' '\n' | sort | uniq) <(awk '{print $1;}' $lang/words.txt) | \
    sort -u | comm -23 - <(awk '{print $1;}' $lang/words.txt | sort -u) \
  > $kws_data_dir/keywords.newwords.txt
  word_id=`tail -n1 $lang/words.txt | awk '{print $2;}'`
  word_id=$(($word_id+1))
  cat $kws_data_dir/keywords.newwords.txt | \
    awk -v word_id="$word_id" '{print $0 " " word_id; word_id += 1;}' >> $kws_data_dir/words.txt
  wc $lang/words.txt $kws_data_dir/words.txt

  cp $keywords $kws_data_dir/keywords.txt
  map_oov=`awk 'BEGIN{a=0}{if ($2>0+a) a=$2} END{print a+10000}' $kws_data_dir/words.txt`
  cat $kws_data_dir/keywords.txt | \
    ${kaldi_path}/local/kws/keywords_to_indices.pl --map-oov $map_oov  $kws_data_dir/words.txt | \
    sort -u > $kws_data_dir/keywords.int
  echo "# of keyword queries: $(wc -l $kws_data_dir/keywords.txt | awk '{print $1}')"

  cat $kws_data_dir/keywords.txt | \
    ${kaldi_path}/local/kws/keywords_to_oov.pl --map-oov $map_oov  $kws_data_dir/words.txt | \
    sort -u > $kws_data_dir/keywords.oovs

  # https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5d/local/kws_setup.sh
  if [[ $create_catetories == "true" ]]; then 
    cat $kws_data_dir/keywords.txt | ${kaldi_path}/local/search/create_categories.pl | ${kaldi_path}/local/search/normalize_categories.pl > $kws_data_dir/categories
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

  ## Ruizhe: we need to generate a new lang to contain those new words in the kw list
  # g2p_exp=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
  # mkdir -p $kws_data_dir/temp
  # # cp $lang/{words.txt,phones.txt} $kws_data_dir/temp/.
  # # cp data/local/dict_nosp/lexicon{,p}.txt $kws_data_dir/temp/.  # TODO: may change
  # prev_lexicon=data/local/dict_nosp/lexiconp.txt

  # get_lexicon () {
  #     _words=$1
  #     _lexiconp=$2
  #     _wdir=$3
  #     _g2p=$4
      
  #     # echo "words:" $_words
  #     # echo "lexiconp:" $_lexiconp
  #     # echo "wdir:" $_wdir

  #     mkdir $_wdir/temp_lex

  #     # words that need to use g2p to generate pronuncation
  #     comm -23 \
  #       <(cat $_words | sort -u) \
  #       <(cat $lexiconp | awk '{print $1}' | sort -u) \
  #     > $_wdir/temp_lex/words_g2p.txt

  #     # words that have entries in lexicon
  #     comm -12 \
  #       <(cat $_words | sort -u) \
  #       <(cat $lexiconp | awk '{print $1}' | sort -u) \
  #     > $_wdir/temp_lex/words_lexicon.txt

  #     wc $_wdir/temp_lex/words_g2p.txt $_wdir/temp_lex/words_lexicon.txt
  #     wc $_words

  #     # pronunciation from g2p
  #     # _g2p=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
  #     _g2p_nbest=3
  #     _g2p_mass=0.95
  #     _script=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/local/apply_g2p.sh
  #     $_script --nj 6 --cmd run.pl --var-counts $_g2p_nbest --var-mass $_g2p_mass \
  #       <(cat $_wdir/temp_lex/words_g2p.txt) $_g2p $_wdir/temp_lex/words_g2p

  #     # pronunciation from lexicon
  #     join -j 1 <(sort $_wdir/temp_lex/words_lexicon.txt) <(sort $_lexiconp) > $_wdir/temp_lex/words_lexicon.lex

  #     # merge the two lexicons
  #     cat $_wdir/temp_lex/words_lexicon.lex $_wdir/temp_lex/words_g2p/lexicon.lex \
  #       | tr '[:upper:]' '[:lower:]' > $_wdir/temp_lex/lexicon.txt
  #     wc $_words $_wdir/temp_lex/lexicon.txt

  #     # echo "The result is in: $_wdir/temp_lex/lexicon.txt"
  #     # echo "You can remove the temporary dir: rm -r $_wdir/temp_lex"
  # }
  # get_lexicon $kws_data_dir/words.txt $prev_lexicon $kws_data_dir $g2p_exp
  # # mv $kws_data_dir/temp_lex/lexicon.txt $kws_data_dir/lexicon.txt

  # mkdir -p $kws_data_dir/temp/dict_nosp
  # cp data/local/dict_nosp/{nonsilence_phones.txt,optional_silence.txt,silence_phones.txt} $kws_data_dir/temp/dict_nosp/.
  # cp $kws_data_dir/temp_lex/lexicon.txt $kws_data_dir/temp/dict_nosp/.

  # utils/prepare_lang.sh $kws_data_dir/temp/dict_nosp/ \
  #     "<unk>"  $kws_data_dir/temp/local/lang_nosp $kws_data_dir/temp/lang_nosp

  ## in many cases, when the reference hits are given, the followin two steps \
  ## are not needed
  ## we create the alignments of the data directory
  ## this is only so that we can obtain the hitlist
  steps/align_fmllr.sh --nj 5 --cmd "$cmd" --beam 10 --retry_beam 60 \
     $data_dir $lang exp/tri3 exp/tri3b_ali_$data

  msg=`grep "Done.*,\serrors\son" exp/tri3b_ali_$data/log/align_pass2.*.log |\
    grep -v "Done.*,\serrors\son\s0" -`
  if [[ ! -z $msg ]]; then
    echo "[Warning] These utterances do not have alignment:" | grep --color "Warning"
    echo "          You may need to manually inspect them, or use larger beam or retry_beam"

    grep "Done.*,\serrors\son" exp/tri3b_ali_$data/log/align_pass2.*.log |\
        grep -v "Done.*,\serrors\son\s0" -
      
    grep --color "Did not successfully decode file" exp/tri3b_ali_$data/log/align_pass2.*.log
  fi

  ${kaldi_path}/local/kws/create_hitlist.sh $data_dir $lang ${kaldi_path}/data/local/lang \
    ${kaldi_path}/exp/tri3b_ali_$data $kws_data_dir
fi

if [ $stage -le 3 ] ; then
    log "Stage 3: Generate *.eps2.fsts for the keywords"
    
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
    ${kaldi_path}/local/kws/compile_keywords.sh $kws_data_dir $(dir $words) $kws_data_dir/tmp.2
    cp $kws_data_dir/tmp.2/keywords.fsts $kws_data_dir/keywords.fsts

    # convert keywords.fsts to keywords.eps2.fsts
    script=/export/fs04/a12/rhuang/kws/kws-release/scripts/kws_py/add_esp2_to_fsts.py
    python3 $script \
      --fsts $kws_data_dir/keywords.fsts \
      --eps2 `grep "<eps2>" $words | awk '{print $2}'` \
      > $kws_data_dir/keywords.eps2.fsts
    
    wc -l $kws_data_dir/keywords.fsts $kws_data_dir/keywords.eps2.fsts
    log "Done: `wc $kws_data_dir/keywords.eps2.fsts`"
fi 