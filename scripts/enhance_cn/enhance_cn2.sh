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
      awk '{print "<"$1"> 1 "$1;}' \
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
  fstarcsort --sort_type=ilabel > $wdir/L1.fst

ls -lah $wdir/L1.fst



