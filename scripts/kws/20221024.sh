########################################
# clean text again:
########################################

# find
cat data/callhome_dev/text | awk '{$1=""}1' | \
    tr ' ' '\n' | sort | uniq | sort | \
    grep "-" | grep -v '\-$' | wc


cat data/callhome_dev/text | awk '{$1=""}1' |     tr ' ' '\n' | sort | uniq | sort |     grep "-" | grep -v '\-$' >a.txt
# mannually edit a.txt, then create a mapping
cat a.txt | awk '{a=$0; gsub(/-/, " ", a); print $0" "a;}' > aa.txt

# https://stackoverflow.com/questions/12400217/replace-a-field-with-values-specified-in-another-file
# awk 'FNR==NR { array[$1]=$2; next } { for (i in array) gsub(i, array[i]) }1' master.txt file.txt
awk 'FNR==NR { w=""; for(i=2;i<=NF;++i){w=w" "$i;}; array[$1]=substr(w, 2); next } { for (i in array) gsub(i, array[i]) }1' aa.txt data/callhome_dev/text > text.txt
vimdiff data/callhome_dev/text text.txt
mv data/callhome_dev/text data/callhome_dev/text.backup.20221024
cp text.txt data/callhome_dev/text

# how to clean keywords list manually
# 1. do kws with the list
# 2. from the per_category_score.txt file, remove the keywords with 0 #Targ -- those words have problem in the reference text or in force alignment
# 3. remove those "double-counted" keywords, which are: (1) multi-word phrases; (2) each of the component word is also in the kw list; (3) their #Targ are the same. If so, only keep the longest phrase
# 4. browse per_category_score.txt by the length of the keywords, remove short and non-sense keywords
# 5. it seems there are too many named entities like people's names
# 6. There are 450/1939 words whose STWV=0 => we need to increase kaldi's lexicon coverage
#      - 50 of them are distractors and should have 0 hits
#      - 290 of them have count=1 in the dev ref text, 69 have count=2
#        These words should have high TF-IDF, but they are very hard for the ASR system (kinda like zero-shut learning)
#        这样选出来的词，太长尾了.
#        We should remove some of them: 
#           - remove those extremely rare words
#      - There are 270 words in the kwlist which are considered as new words to the swbd lexicon



# callhome_dev
cat > $kws_data_dir/keywords_to_remove.txt <<EOF
KW-00023
KW-00092
KW-00434
KW-00435
KW-00657
KW-00752
KW-00753
KW-00945
KW-01114
KW-01115
KW-01131
KW-01162
KW-01206
KW-01236
KW-01353
KW-01356
KW-01357
KW-01360
KW-01361
KW-01363
KW-01364
KW-01421
KW-01615
KW-01616
KW-01666
KW-01766
KW-01767
KW-01774
KW-01775
KW-02065
KW-02097
KW-02098
KW-02122
KW-02126
KW-02127
KW-02471
KW-00169
KW-00173
KW-00220
KW-00285
KW-00446
KW-00454
KW-00502
KW-00930
KW-00932
KW-00938
KW-01340
KW-01797
KW-02033
KW-02312
KW-02326
KW0-02490
KW0-02508
KW-02196
KW-02379
KW-00354
KW-00268
KW-00511
KW-00958
KW-01229
KW-01609
KW-02275
KW0-02503
KW0-02519
KW-01143
EOF

# filter out the keywords defined in keywords_to_remove.txt
awk 'FNR==NR { array[$1]=$1; next } { if (! ($1 in array)) {print;} }' \
    $kws_data_dir/keywords_to_remove.txt $keywords > $kws_data_dir/keywords.filtered1.txt
wc $kws_data_dir/keywords_to_remove.txt $kws_data_dir/keywords.txt $kws_data_dir/keywords.filtered1.txt

# filter out the keywords which will cause "double-counting" in computer TWVs
python3 /export/fs04/a12/rhuang/kws/kws-release/scripts/kws_py/double_counted_kw.py \
  --per_category_score /export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_callhome_dev_1.0_50_coe_standard_new2//kws_indices/kws_results/details_50/per-category-score.txt \
  --keywords $kws_data_dir/keywords.filtered1.txt \
  > $kws_data_dir/keywords_to_remove2.txt

awk 'FNR==NR { array[$1]=$1; next } { if (! ($1 in array)) {print;} }' \
    $kws_data_dir/keywords_to_remove2.txt $kws_data_dir/keywords.filtered1.txt > $kws_data_dir/keywords.filtered2.txt
wc $kws_data_dir/keywords_to_remove2.txt $kws_data_dir/keywords.filtered1.txt $kws_data_dir/keywords.filtered2.txt

# remove words that contains ' or .
cat $kws_data_dir/keywords.filtered2.txt | sed "/'/d" | sed "/\./d" > $kws_data_dir/keywords.filtered3.txt
wc $kws_data_dir/keywords.filtered3.txt

########################################
# Which lexicon is good?
########################################

# 1. add callhome words
# 2. 241k vocab
# 3. cmu dict
# The above are not a fair comparison, as espnet model doesn't have access to them. They are considered as extra resources.
# However, swbd train+fisher words may be a good set to consider

# use a large vocab for k2
# 2022-03-07:02:24:51 b16 /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12
lexicon_241k=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/lang_bpe_2000_241k/words.txt

# 241k
/export/fs04/a12/rhuang/opensat/kaldi/egs/opensat20/s5/data/lang_nosp_241k/words.txt
/export/fs04/a12/rhuang/opensat/kaldi/egs/opensat20/s5/data/local/dict_nosp/lexicon.txt

# cmu
cmu_lexicon=/export/fs04/a12/rhuang/opensat/kaldi/egs/opensat20/s5/data/local/dict/lexicon.txt
# https://github.com/kaldi-asr/kaldi/blob/master/egs/wsj/s5/utils/prepare_lang.sh
cat $cmu_lexicon | awk '{print $1}' | sort | uniq  | awk '
  BEGIN {
    print "<eps> 0";
  }
  {
    if ($1 == "<s>") {
      print "<s> is in the vocabulary!" | "cat 1>&2"
      exit 1;
    }
    if ($1 == "</s>") {
      print "</s> is in the vocabulary!" | "cat 1>&2"
      exit 1;
    }
    printf("%s %d\n", $1, NR);
  }
  END {
    printf("#0 %d\n", NR+1);
    printf("<s> %d\n", NR+2);
    printf("</s> %d\n", NR+3);
  }' | tr '[:upper:]' '[:lower:]' > cmu_words.txt

# get the extremely rare words
words_241k=/export/fs04/a12/rhuang/opensat/kaldi/egs/opensat20/s5/data/lang_nosp_241k/words.txt
words_cmu_123k=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/cmu_words.txt
awk 'FNR==NR { array[$1]=$2; next } { 
    flag=0;
    for(i=2; i<=NF; ++i) {
        if (! ($i in array)) {
            flag=1;
            break;
        }
    } 
    if (flag == 1) {
        print $0;
    }
}' \
$words_cmu_123k $keywords > $kws_data_dir/keywords_to_remove3.txt
wc $kws_data_dir/keywords_to_remove3.txt

# remove the extremely rare words
awk 'FNR==NR { array[$1]=$1; next } { if (! ($1 in array)) {print;} }' \
    $kws_data_dir/keywords_to_remove3.txt $kws_data_dir/keywords.filtered3.txt > $kws_data_dir/keywords.filtered4.txt
wc $kws_data_dir/keywords_to_remove3.txt $kws_data_dir/keywords.filtered3.txt $kws_data_dir/keywords.filtered4.txt

########################################
# Ok, now get a new lexicon for kaldi (expand lexicon)
# We will need to:
#   - get the lexicon and graphs
#   - re-train the language models
#   - decode the data again
#   - the WER might go well-beyond espnet?
########################################

# https://github.com/kaldi-asr/kaldi/blob/master/egs/swbd/s5c/local/swbd1_train_lms.sh
train_text=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/train/text
# zcat /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/lm/fisher/text1.gz > /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/lm/fisher/text1
fisher_text=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/lm/fisher/text1
# /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/local/rnnlm/tuning/run_tdnn_lstm_1e.sh
# /export/fs04/a12/rhuang/kws/kws/run.sh
cat $fisher_text <(awk '{$1=""}1' $train_text) | \
    tr ' ' '\n' | sort | uniq -c | sort -r | awk '{print $2" "$1}' | sort -k1,1 > lm_vocab_kaldi.txt
kaldi_lm_vocab=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/lm_vocab_kaldi.txt  # 70k, but a bit dirty. I will use the one from espnet

# /export/fs04/a12/rhuang/kws/kws-release/scripts/cbs/example.sh
espnet_lm_text=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lm_train.txt
espnet_lm_vocab=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/lm_vocab.txt  # 66k

get_lexicon_for_new_words () {
    _words=$1
    _lexiconp=$2
    _wdir=$3
    _g2p=$4
    
    echo "words: `wc $_words`"
    echo "lexiconp: `wc $_lexiconp`" 
    echo "wdir:" $_wdir

    mkdir $_wdir/temp_lex

    # words that need to use g2p to generate pronuncation
    comm -23 \
      <(cat $_words | awk '{print $1}' | sort -u) \
      <(cat $lexiconp | awk '{print $1}' | sort -u) \
    > $_wdir/temp_lex/words_g2p.txt

    wc $_wdir/temp_lex/words_g2p.txt

    # pronunciation from g2p
    # _g2p=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
    _g2p_nbest=3
    _g2p_mass=0.95
    _script=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/local/apply_g2p.sh
    $_script --nj 16 --cmd queue.pl --var-counts $_g2p_nbest --var-mass $_g2p_mass \
      <(cat $_wdir/temp_lex/words_g2p.txt) $_g2p $_wdir/temp_lex/words_g2p

    echo "The result is in: $_wdir/temp_lex/words_g2p/lexicon.lex"
}
lexicon=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/dict/lexicon.txt
lexiconp=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/dict/lexiconp.txt
g2p_exp=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
get_lexicon_for_new_words $espnet_lm_vocab $lexiconp $(pwd) $g2p_exp
# mv $kws_data_dir/temp_lex/lexicon.txt $kws_data_dir/lexicon.txt

######## make lang ########
wdir=$(pwd)/temp_lang
mkdir -p $wdir/dict_nosp
cp data/local/dict_nosp/{nonsilence_phones.txt,optional_silence.txt,silence_phones.txt,acronyms}* $wdir/dict_nosp/.
# merge lexicons
cat $lexiconp $_wdir/temp_lex/words_g2p/lexicon.lex \
  | tr '[:upper:]' '[:lower:]' | awk '{$2=""}1' | sort -u \
> $wdir/dict_nosp/lexicon.txt
wc $wdir/dict_nosp/lexicon.txt

utils/prepare_lang.sh $wdir/dict_nosp/ \
    "<unk>"  $wdir/local/lang_nosp $wdir/lang_nosp

######## train lm ########
if [ $stage -le 3 ]; then
  fisher_dirs="/export/corpora3/LDC/LDC2004T19/fe_03_p1_tran/ /export/corpora3/LDC/LDC2005T19/fe_03_p2_tran/"
  # local/swbd1_train_lms.sh data/local/train/text \
  #   $wdir/dict_nosp/lexicon.txt $wdir/lm $fisher_dirs

  cd /export/fs04/a12/rhuang/kaldi/egs/swbd/s5c
  local/swbd1_train_lms.sh /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/train/text \
    /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/temp_lang/dict_nosp/lexicon.txt \
    /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/temp_lang/lm \
    /export/corpora3/LDC/LDC2004T19/fe_03_p1_tran/ /export/corpora3/LDC/LDC2005T19/fe_03_p2_tran/
  cd -
fi

has_fisher=true
if [ $stage -le 4 ]; then
  # Compiles G for swbd trigram LM
  LM=$wdir/lm/sw1.o3g.kn.gz
  srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
                         $wdir/lang_nosp $LM $wdir/dict_nosp/lexicon.txt $wdir/lang_nosp_sw1_tg

  # Compiles const G for swbd+fisher 4gram LM, if it exists.
  LM=$wdir/lm/sw1_fsh.o4g.kn.gz
  [ -f $LM ] || has_fisher=false
  if $has_fisher; then
    utils/build_const_arpa_lm.sh $LM $wdir/lang_nosp $wdir/lang_nosp_sw1_fsh_fg
  fi
fi

# Do I need to retrain the acoustic models?
# Try decoding with them!

tag="ep1"
stage=0
. ./cmd.sh

# TODO: need to re-map the *.scp files
# feat-to-dim 'ark,s,cs:apply-cmvn --utt2spk=ark:data/train_30kshort/split30/1/utt2spk scp:data/train_30kshort/split30/1/cmvn.scp scp:data/train_30kshort/split30/1/feats.scp ark:- | add-deltas ark:- ark:- |' -
# apply-cmvn --utt2spk=ark:data/train_30kshort/split30/1/utt2spk scp:data/train_30kshort/split30/1/cmvn.scp scp:data/train_30kshort/split30/1/feats.scp ark:-
# add-deltas ark:- ark:-

for i in $(seq 30); do
  # f=data/train_30kshort/split30/$i/cmvn.scp
  f=data/train_30kshort/split30/$i/feats.scp
  cp $f $f.backup
  sed -i 's/\/export\/b09\/ssegal\/kaldi\/egs\/swbd\/s5c\//\/export\/fs04\/a12\/rhuang\/kws\/kws_exp\/shay\/s5c\//g' $f
done

if [ $stage -le 9 ]; then
  ## Starting basic training on MFCC features
  steps/train_mono.sh --nj 30 --cmd "$train_cmd" \
                      data/train_30kshort $wdir/lang_nosp exp/mono_$tag
fi

if [ $stage -le 10 ]; then
  # steps/align_si.sh --nj 30 --cmd "$train_cmd" \
  #                   data/train_100k_nodup data/lang_nosp exp/mono exp/mono_ali

  # steps/train_deltas.sh --cmd "$train_cmd" \
  #                       3200 30000 data/train_100k_nodup data/lang_nosp exp/mono_ali exp/tri1

  (
    graph_dir=$wdir/exp/tri1/graph_nosp_sw1_tg
    $train_cmd $graph_dir/mkgraph.log \
               utils/mkgraph.sh $wdir/lang_nosp_sw1_tg exp/tri1 $graph_dir
    steps/decode_si.sh --nj 30 --cmd "$decode_cmd" --config conf/decode.config \
                       $graph_dir data/eval2000 exp/tri1/decode_eval2000_nosp_sw1_tg_$tag
  ) &
fi

if [ $stage -le 11 ]; then
  steps/align_si.sh --nj 30 --cmd "$train_cmd" \
                    data/train_100k_nodup data/lang_nosp exp/tri1 exp/tri1_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
                        4000 70000 data/train_100k_nodup data/lang_nosp exp/tri1_ali exp/tri2

  (
    # The previous mkgraph might be writing to this file.  If the previous mkgraph
    # is not running, you can remove this loop and this mkgraph will create it.
    while [ ! -s data/lang_nosp_sw1_tg/tmp/CLG_3_1.fst ]; do sleep 60; done
    sleep 20; # in case still writing.
    graph_dir=exp/tri2/graph_nosp_sw1_tg
    $train_cmd $graph_dir/mkgraph.log \
               utils/mkgraph.sh data/lang_nosp_sw1_tg exp/tri2 $graph_dir
    steps/decode.sh --nj 30 --cmd "$decode_cmd" --config conf/decode.config \
                    $graph_dir data/eval2000 exp/tri2/decode_eval2000_nosp_sw1_tg
  ) &
fi

if [ $stage -le 12 ]; then
  # The 100k_nodup data is used in the nnet2 recipe.
  steps/align_si.sh --nj 30 --cmd "$train_cmd" \
                    data/train_100k_nodup data/lang_nosp exp/tri2 exp/tri2_ali_100k_nodup

  # From now, we start using all of the data (except some duplicates of common
  # utterances, which don't really contribute much).
  steps/align_si.sh --nj 30 --cmd "$train_cmd" \
                    data/train_nodup data/lang_nosp exp/tri2 exp/tri2_ali_nodup

  # Do another iteration of LDA+MLLT training, on all the data.
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
                          6000 140000 data/train_nodup data/lang_nosp exp/tri2_ali_nodup exp/tri3

  (
    graph_dir=exp/tri3/graph_nosp_sw1_tg
    $train_cmd $graph_dir/mkgraph.log \
               utils/mkgraph.sh data/lang_nosp_sw1_tg exp/tri3 $graph_dir
    steps/decode.sh --nj 30 --cmd "$decode_cmd" --config conf/decode.config \
                    $graph_dir data/eval2000 exp/tri3/decode_eval2000_nosp_sw1_tg
  ) &
fi

cp exp/tri3/ali_prev/ali.* exp/tri3/.
if [ $stage -le 13 ]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.
  steps/get_prons.sh --cmd "$train_cmd" data/train_nodup $wdir/lang_nosp exp/tri3
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
                                  $wdir/dict_nosp exp/tri3/pron_counts_nowb.txt exp/tri3/sil_counts_nowb.txt \
                                  exp/tri3/pron_bigram_counts_nowb.txt $wdir/dict

  utils/prepare_lang.sh $wdir/dict "<unk>" $wdir/local/lang $wdir/lang
  LM=$wdir/lm/sw1.o3g.kn.gz
  srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
                         $wdir/lang $LM $wdir//dict/lexicon.txt $wdir/lang_sw1_tg
  LM=$wdir/lm/sw1_fsh.o4g.kn.gz
  if $has_fisher; then
    utils/build_const_arpa_lm.sh $LM $wdir/lang $wdir/lang_sw1_fsh_fg
  fi

  (
    graph_dir=$wdir/exp/tri3/graph_sw1_tg
    $train_cmd $graph_dir/mkgraph.log \
               utils/mkgraph.sh $wdir/lang_sw1_tg exp/tri3 $graph_dir
    steps/decode.sh --nj 30 --cmd "$decode_cmd" --config conf/decode.config \
                    $graph_dir data/eval2000 exp/tri3/decode_eval2000_sw1_tg_$tag
  ) &
fi

# Not sure why I need to re-make MFCC features
# Oh it is different directories:
# /export/fs04/a12/rhuang/kws/kws/run.sh
cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
# cd /export/fs04/a12/rhuang/kws/kws  # exp/ in there will actually point to the one in shay/s5c

mfccdir=mfcc_hires
nj=50 # number of parallel jobs,

for data in std2006_dev std2006_eval; do
  if [ ! -f data/$data/wav.scp.16000backup ]; then
    cp data/$data/wav.scp data/$data/wav.scp.16000backup
  fi
  sed -i 's/16000 dither/8000 dither/g' data/$data/wav.scp
done

# Create MFCCs for the eval set
for data in eval2000 std2006_dev std2006_eval callhome_dev callhome_eval; do
  utils/copy_data_dir.sh data/$data data/${data}_hires
  steps/make_mfcc.sh --cmd "$train_cmd" --nj $nj --mfcc-config conf/mfcc_hires.conf \
      data/${data}_hires exp/make_hires/${data} $mfccdir;
  steps/compute_cmvn_stats.sh data/${data}_hires exp/make_hires/${data} $mfccdir;
  utils/fix_data_dir.sh data/${data}_hires  # remove segments with problems
done

# for data in std2006_dev std2006_eval; do
#   data=${data}_hires
#   steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $nj \
#     data/${data} exp/nnet2_online/extractor exp/nnet2_online/ivectors_${data}_$tag
# done

######### Chain Model #########
# https://github.com/kaldi-asr/kaldi/blob/master/egs/swbd/s5c/local/chain/tuning/run_tdnn_7r.sh
# make graph again
lang=data/lang_chain_2y_$tag
if [ $stage -le 10 ]; then
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  rm -rf $lang
  cp -r $wdir/lang $lang
  silphonelist=$(cat $lang/phones/silence.csl)
  nonsilphonelist=$(cat $lang/phones/nonsilence.csl)
  # Use our special topology... note that later on may have to tune this
  # topology.
  steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
fi

suffix=_sp
treedir=exp/chain/tri5_7d_tree$suffix

dir=exp/chain/tdnn7r_sp/
if [ $stage -le 14 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 $wdir/lang_sw1_tg $dir $dir/graph_sw1_tg_$tag
fi

### tdnn
dir=exp/chain/tdnn7r_sp/
graph_dir=exp/chain/tdnn7r_sp/graph_sw1_tg_$tag/
# if [ -e data/rt03 ]; then maybe_rt03=rt03; else maybe_rt03= ; fi
iter_opts=
decode_nj=50
has_fisher=true
rm $dir/.error 2>/dev/null || true
for decode_set in eval2000 $maybe_rt03; do
    (
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
        --nj $decode_nj --cmd "$decode_cmd" $iter_opts \
        --online-ivector-dir exp/nnet3/ivectors_${decode_set} \
        $graph_dir data/${decode_set}_hires \
        $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_sw1_tg_$tag || exit 1;
    if $has_fisher; then
        steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
          data/lang_sw1_{tg,fsh_fg} data/${decode_set}_hires \
          $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_sw1_{tg,fsh_fg}_$tag || exit 1;
    fi
    ) || touch $dir/.error &
done
wait
if [ -f $dir/.error ]; then
  echo "$0: something went wrong in decoding"
fi