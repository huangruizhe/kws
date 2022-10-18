# Get a subset of L1
# 1) Create a big L1
# 2) Create the L1 for each recording

data=callhome_dev

nbest_dir=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/nbest_topk/
kws_data_dir=/export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_$data
# keywords=/export/fs04/a12/rhuang/kws/kws/data0/$data/kws/keywords.$data.txt     # std2006
keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt  # callhome
scale=1.0
nsize=50
# lats_dir=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_${data}_${scale}_${nsize}
lats_dir=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50

wdir=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/test/confusion/

########################################
# Collect all words in clats
########################################


zcat $lats_dir/clat_eps2/clat.*.eps2.gz | \
  awk 'BEGIN {flag=0; } {
      if (NF == 1) {
          flag=1;
          # print;
      } else if (flag == 1) {
          if (length($0) == 0) {
              flag=0;
          } else {
              print;
          }
      } else {
          ;
      }
  }' | \
  cut -d" " -f3 | \
  tr ' ' '\n' | \
  sed '/^[[:space:]]*$/d' | sed -r '/^.{,3}$/d' | sed -r '/^\[.*\]$/d' |\
  sed '/\[/d' | sed '/\]/d' | \
  sed -r '/^.*\-$/d' | sed -r '/^\-.*$/d' | \
  sed -r '/^<.*>$/d' |\
  sort | uniq -c | sort -r \
> $wdir/all_clats_words.txt
wc $wdir/all_clats_words.txt

top_thres=100
cat $wdir/all_clats_words.txt |\
  head -n $top_thres | awk '{print $2}' \
> $wdir/stopwords.txt

cat $wdir/all_clats_words.txt | perl -e '
  open(W, "<'$wdir/stopwords.txt'") ||
    die "Fail to open stopwords: '$wdir/stopwords.txt'\n";
  my %stopwords;
  while (<W>) {
    chomp;
    $stopwords{$_} = 1;
  }
  while (<>) {
    chomp;
    my $line = $_;
    my @col = split();
    @col != 2 && die "Bad line in input file: $_\n";
    if (! defined($stopwords{$col[1]})) {
      print "$line\n";
    }
  }' > $wdir/all_clats_words_filtered.txt
wc $wdir/all_clats_words_filtered.txt

########################################
# generate pronunciation for the cached words, via lexicon or g2p
########################################

get_lexicon () {
    _words=$1
    _lexiconp=$2
    _wdir=$3
    
    echo "words:" $_words
    echo "lexiconp:" $_lexiconp
    echo "wdir:" $_wdir

    mkdir $_wdir/temp_lex

    # words that need to use g2p to generate pronuncation
    comm -23 \
      <(cat $_words | sort -u) \
      <(cat $lexiconp | awk '{print $1}' | sort -u) \
    > $_wdir/temp_lex/words_g2p.txt

    # words that have entries in lexicon
    comm -12 \
      <(cat $_words | sort -u) \
      <(cat $lexiconp | awk '{print $1}' | sort -u) \
    > $_wdir/temp_lex/words_lexicon.txt

    wc $_wdir/temp_lex/words_g2p.txt $_wdir/temp_lex/words_lexicon.txt
    wc $_words

    # pronunciation from g2p
    _g2p=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
    _g2p_nbest=10
    _g2p_mass=0.95
    _script=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/local/apply_g2p.sh
    _nj=8
    $_script --nj $_nj --cmd run.pl --var-counts $_g2p_nbest --var-mass $_g2p_mass \
      <(cat $_wdir/temp_lex/words_g2p.txt) $_g2p $_wdir/temp_lex/words_g2p

    # pronunciation from lexicon
    join -j 1 <(sort $_wdir/temp_lex/words_lexicon.txt) <(sort $_lexiconp) > $_wdir/temp_lex/words_lexicon.lex

    # merge the two lexicons
    wc $_wdir/temp_lex/words_lexicon.lex $_wdir/temp_lex/words_g2p/lexicon.lex
    cat $_wdir/temp_lex/words_lexicon.lex $_wdir/temp_lex/words_g2p/lexicon.lex \
      | tr '[:upper:]' '[:lower:]' > $_wdir/temp_lex/lexicon.txt
    wc $_words $_wdir/temp_lex/lexicon.txt

    echo "The result is in: $_wdir/temp_lex/lexicon.txt"
    echo "You can remove the temporary dir: rm -r $_wdir/temp_lex"
}

lexicon=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/dict/lexicon.txt
lexiconp=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/dict/lexiconp.txt

cat $wdir/all_clats_words_filtered.txt | awk '{print $2}' > $wdir/L1_all_words.txt

get_lexicon $wdir/L1_all_words.txt $lexiconp $wdir

# remove words that has pronunciation less than 2 phones:
cat test/confusion/temp_lex/lexicon.txt | awk "NF>4" > $wdir/L1_all.lex
mv test/confusion/temp_lex test/confusion/L1_all_g2p

########################################
# get L1 for each recording
########################################

recording_id=en_4315_0B

zcat $lats_dir/clat_eps2/clat.*.eps2.gz | \
    awk -v recording_id="$recording_id" 'BEGIN {flag=0; } {
        if ($0 ~ recording_id) {
            flag=1;
            # print;
        } else if (flag == 1) {
            if (length($0) == 0) {
                flag=0;
            } else {
                print;
            }
        } else {
            ;
        }
    }' | \
    cut -d" " -f3 | \
    tr ' ' '\n' | \
    sed '/^[[:space:]]*$/d' | sed -r '/^.{,3}$/d' | sed -r '/^\[.*\]$/d' |\
    sed '/\[/d' | sed '/\]/d' | \
    sed -r '/^.*\-$/d' | sed -r '/^\-.*$/d' | \
    sed -r '/^<.*>$/d' |\
    sort | uniq -c | sort -r \
> $wdir/freq_$recording_id.txt
wc $wdir/freq_$recording_id.txt

# Intersect L1_all with the recording words
# All filtering has been done to L1_all, so no need to do other filtering here anymore
join -j 1 <(awk '{print $2}' $wdir/freq_$recording_id.txt | sort) <(sort $wdir/L1_all.lex) \
    > $wdir/L1_${recording_id}.lex
wc $wdir/L1_${recording_id}.lex

########################################
# step3 generate L1.fst
########################################

# https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5c/local/datasets/extra_kws.sh
# https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5b/local/generate_proxy_keywords.sh
# https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5b/local/kws_data_prep_proxy.sh

wdir=test/confusion
L1_lex=$wdir/L1_${recording_id}.lex

kaldi_asr=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
oldlang=${kaldi_asr}/data/lang_sw1_fsh_fg

phone_start=3
pron_probs_param="--pron-probs";

phone_lex=$wdir/phone.lex
if [[ ! -f $phone_lex ]]; then
    cat <(cat $oldlang/phones.txt | awk "NF=1" | sed 's/_.*$//') \
      <(cat $wdir/L1_all.lex | awk '{for(i='$phone_start'; i <= NF; i++) {print $i;}}' | tr ' ' '\n' | sort -u) | \
      sort -u | grep -v "#" | grep -v "<eps>" | \
      awk '{print "<"$1"> 0.0000001 "$1;}' \
    > $phone_lex
    wc $phone_lex
fi

# create our new words.txt
if [[ ! -f $wdir/words.txt ]]; then
    cat <(awk '{print $1;}' $oldlang/words.txt) <(awk '{print $1;}' $wdir/L1_all.lex) <(awk '{print $1;}' $wdir/phone.lex) | \
        sort -u | comm -23 - <(awk '{print $1;}' $oldlang/words.txt | sort -u) \
    > $wdir/new_words.txt
    cp $oldlang/words.txt $wdir/words.txt
    word_id=`tail -n1 $oldlang/words.txt | awk '{print $2;}'`
    word_id=$(($word_id+1))
    cat $wdir/new_words.txt | \
        awk -v word_id="$word_id" '{print $0 " " word_id; word_id += 1;}' >> $wdir/words.txt
    wc $wdir/words.txt
fi

cat $phone_lex >> $L1_lex
wc $L1_lex

ndisambig=`utils/add_lex_disambig.pl \
  $pron_probs_param $L1_lex $wdir/L1_disambig.lex`
ndisambig=$[$ndisambig+1]; # add one disambig symbol for silence in lexicon FST.
( for n in `seq 0 $ndisambig`; do echo '#'$n; done ) > $wdir/disambig.txt
wc $wdir/disambig.txt

cat $L1_lex |\
  awk '{for(i='$phone_start'; i <= NF; i++) {print $i;}}' |\
  sort -u | sed '1i\<eps>' |\
  cat - $wdir/disambig.txt | awk 'BEGIN{x=0} {print $0"\t"x; x++;}' \
  > $wdir/phones.txt
wc $wdir/phones.txt

# Since we will take the reverse of L1, so we need to add the disambiguation symbols
phone_disambig_symbol=`grep \#0 $wdir/phones.txt | awk '{print $2}'`
word_disambig_symbol=`grep \#0 $wdir/words.txt | awk '{print $2}'`
phone_disambig_symbols=`grep \# $wdir/phones.txt |\
  awk '{print $2}' | tr "\n" " "`
word_disambig_symbols=`grep \# $wdir/words.txt |\
  awk '{print $2}' | tr "\n" " "`
cat $wdir/L1_disambig.lex |\
  utils/make_lexicon_fst.pl $pron_probs_param - |\
  fstcompile --isymbols=$wdir/phones.txt \
  --osymbols=$wdir/words.txt - |\
  fstaddselfloops "echo $phone_disambig_symbol |" \
  "echo $word_disambig_symbol |" |\
  fstdeterminize | fstrmsymbols "echo $phone_disambig_symbols|" |\
  fstrmsymbols --remove-from-output=true "echo $word_disambig_symbols|" |\
  fstarcsort --sort_type=ilabel > $wdir/L1_${recording_id}.fst

ls -lah $wdir/L1_${recording_id}.fst

########################################
# Generate prounciation L2 for all sausage bins in the recording
# Generate L2.fst
########################################

python=/export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet_gpu/bin/python
get_bin_words_py=/export/fs04/a12/rhuang/kws/kws-release/scripts/enhance_cn/get_bin_words.py

recording_id=en_4315_0B

wdir=test/confusion
L1_lex=$wdir/L1_${recording_id}.lex

zcat $lats_dir/clat_eps2/clat.*.eps2.gz | \
    awk -v recording_id="$recording_id" 'BEGIN {flag=0; } {
        if ($0 ~ recording_id) {
            flag=1;
            print;
        } else if (flag == 1) {
            if (length($0) == 0) {
                flag=0;
                print;
            } else {
                print;
            }
        } else {
            ;
        }
    }' | \
    $python $get_bin_words_py --l1_lex $L1_lex --w2keys $wdir/w2keys_${recording_id}.gz \
> $wdir/bin_words_${recording_id}.txt
wc $wdir/bin_words_${recording_id}.txt

join -j 1 <(awk '{print $2}' $wdir/bin_words_${recording_id}.txt | sort) <(sort $wdir/L1_all.lex) \
    > $wdir/L2_${recording_id}.lex
wc $wdir/L2_${recording_id}.lex

cat $wdir/L2_${recording_id}.lex |\
  utils/make_lexicon_fst.pl $pron_probs_param - |\
  fstcompile --isymbols=$wdir/phones.txt \
  --osymbols=$wdir/words.txt - |\
  fstinvert | fstarcsort --sort_type=olabel > $wdir/L2_${recording_id}.fst
ls -lah $wdir/L2_${recording_id}.fst

########################################
# step4 generate E or E' from the counts
########################################

confusion_matrix=$wdir/confusions.txt
count_cutoff=1      # Minimal count to be considered in the confusion matrix;

# Compiles E.fst
confusion_matrix_param=""
if [ ! -z $confusion_matrix ]; then
  echo "$0: Using confusion matrix, normalizing"
  /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/local/count_to_logprob.pl \
    --cutoff $count_cutoff \
    $confusion_matrix $wdir/confusionp.txt
  confusion_matrix_param="--confusion-matrix $wdir/confusionp.txt"
fi
ls -lah $wdir/confusionp.txt

cat $wdir/phones.txt |\
  grep -v -E "<.*>" | grep -v "SIL" | awk '{print $1;}' |\
  /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/local/build_edit_distance_fst.pl \
    --boundary-off=true \
    $confusion_matrix_param - - |\
    fstcompile --isymbols=$wdir/phones.txt \
    --osymbols=$wdir/phones.txt - $wdir/E.fst
ls -lah $wdir/E.fst

########################################
# step6 compose K x L2 x E x L1'
########################################

nj=10
cmd=run.pl

# https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5b/local/kws_data_prep_proxy.sh
beam=-1             # Beam for proxy FST, -1 means no prune
phone_beam=-1       # Beam for KxL2xE FST, -1 means no prune
nbest=-1            # Use top n best proxy keywords in proxy FST, -1 means all
                    # proxies
phone_nbest=100      # Use top n best phone sequences in KxL2xE, -1 means all
                    # phone sequences
phone_cutoff=5      # We don't generate proxy keywords for OOV keywords that
                    # have less phones than the specified cutoff as they may
                    # introduce a lot false alarms

L1_fst=$wdir/L1_${recording_id}.fst
L2_fst=$wdir/L2_${recording_id}.fst

# Pre-composes L2 and E, for the sake of efficiency
fstcompose $L2_fst $wdir/E.fst |\
  fstarcsort --sort_type=ilabel > $wdir/L2xE_${recording_id}.fst

keywords_text=$wdir/bin_words_${recording_id}.txt
keywords_int=$wdir/bin_words_${recording_id}.int
cat $keywords_text |\
  utils/sym2int.pl -f 2- $wdir/words.txt | sort -R > $keywords_int

# less $keywords_int

nof_keywords=`cat $keywords|wc -l`
if [ $nj -gt $nof_keywords ]; then
  nj=$nof_keywords
  echo "$0: Too many number of jobs, using $nj instead"
fi

# Generates the proxy keywords
mkdir -p $wdir/split/log
time $cmd JOB=1:$nj $wdir/split/log/proxy.JOB.log \
  split -n r/JOB/$nj $keywords_int \| \
  generate-proxy-keywords --verbose=1 \
  --proxy-beam=$beam --proxy-nbest=$nbest \
  --phone-beam=$phone_beam --phone-nbest=$phone_nbest \
  $wdir/L2xE_${recording_id}.fst $L1_fst ark:- ark:$wdir/split/proxy.JOB.fsts ark,t:$wdir/split/proxy.JOB.kwlist.txt

proxy_fsts=""
proxy_kws=""
for j in `seq 1 $nj`; do
  proxy_fsts="$proxy_fsts $wdir/split/proxy.$j.fsts"
  proxy_kws="$proxy_kws $wdir/split/proxy.$j.kwlist.txt"
done
cat $proxy_fsts > $wdir/expanded_keywords_${recording_id}.fsts
cat $proxy_kws | utils/int2sym.pl -f 3- $wdir/words.txt > $wdir/expanded_keywords_${recording_id}.txt

echo "Done: `wc $wdir/expanded_keywords_${recording_id}.txt`"
cat $wdir/expanded_keywords_${recording_id}.txt | awk 'NF<7' | sed 's/<.*>/ /g' \
  | awk 'NF>=3' \
> $wdir/expanded_keywords_${recording_id}.final.txt
wc $wdir/expanded_keywords_${recording_id}.final.txt

#### debug:

kw=side
grep "^$kw" $wdir/expanded_keywords_${recording_id}.txt | awk 'NF<7' | sed 's/<.*>/ /g' | awk 'NF>=3'
grep "^beside" $L1_lex
grep "s ah" test/confusion/confusionp.txt

# 最后proxy的分数的算法是，把下面三者相加
# 1. L2里proxy的发音的log prob(需对prob取log)
# 2. test/confusion/confusionp.txt里的编辑操作的log prob求和
# 3. L1里proxy的发音的log prob(需对prob取log)

split -n r/1/$nj test/confusion/keywords.int | \
generate-proxy-keywords --verbose=0 \
  --proxy-beam=$beam --proxy-nbest=$nbest \
  --phone-beam=$phone_beam --phone-nbest=$phone_nbest \
  $wdir/L2xE.fst $wdir/L1.fst ark:- ark:$wdir/split/proxy.1.fsts ark,t:-

split -n r/1/$nj $keywords_int | \
generate-proxy-keywords --verbose=0 \
  --proxy-beam=$beam --proxy-nbest=$nbest \
  --phone-beam=$phone_beam --phone-nbest=$phone_nbest \
  $wdir/L2xE.fst $wdir/L1.fst ark:- ark:$wdir/split/proxy.1.fsts ark,t:-


fstcopy ark:$L1_fst ark,t:-