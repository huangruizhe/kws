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

get_lexicon () {
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

    # words that have entries in lexicon
    comm -12 \
      <(cat $_words | awk '{print $1}' | sort -u) \
      <(cat $lexiconp | awk '{print $1}' | sort -u) \
    > $_wdir/temp_lex/words_lexicon.txt

    wc $_wdir/temp_lex/words_g2p.txt $_wdir/temp_lex/words_lexicon.txt
    wc $_words

    # pronunciation from g2p
    # _g2p=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
    _g2p_nbest=3
    _g2p_mass=0.95
    _script=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/local/apply_g2p.sh
    $_script --nj 6 --cmd run.pl --var-counts $_g2p_nbest --var-mass $_g2p_mass \
      <(cat $_wdir/temp_lex/words_g2p.txt) $_g2p $_wdir/temp_lex/words_g2p

    # pronunciation from lexicon
    join -j 1 <(sort -k1,1 $_wdir/temp_lex/words_lexicon.txt) <(sort -k1,1 $_lexiconp) > $_wdir/temp_lex/words_lexicon.lex

    # merge the two lexicons
    cat $_wdir/temp_lex/words_lexicon.lex $_wdir/temp_lex/words_g2p/lexicon.lex \
      | tr '[:upper:]' '[:lower:]' > $_wdir/temp_lex/lexicon.txt
    wc $_words $_wdir/temp_lex/lexicon.txt

    echo "The result is in: $_wdir/temp_lex/lexicon.txt"
    echo "You can remove the temporary dir: rm -r $_wdir/temp_lex"
}
lexicon=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/dict/lexicon.txt
lexiconp=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/dict/lexiconp.txt
g2p_exp=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
get_lexicon $espnet_lm_vocab $lexiconp $(pwd) $g2p_exp
# mv $kws_data_dir/temp_lex/lexicon.txt $kws_data_dir/lexicon.txt

# make lang
wdir=temp_lang
mkdir -p $wdir/dict_nosp
cp data/local/dict_nosp/{nonsilence_phones.txt,optional_silence.txt,silence_phones.txt} $wdir/dict_nosp/.
cat $(pwd)/temp_lex/lexicon.txt | awk '{$2=""}1' | sort -u > $wdir/dict_nosp/lexicon.txt

utils/prepare_lang.sh $wdir/dict_nosp/ \
    "<unk>"  $wdir/local/lang_nosp $wdir/lang_nosp



# train lm