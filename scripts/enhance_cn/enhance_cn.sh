# https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5b/local/generate_proxy_keywords.sh

echo "Proxies keywords are generated using:"
echo "K x L2 x E x L1'"
echo "where K is a keyword FST, L2 is a lexicon that contains pronunciations"
echo "of keywords in K, E is an edit distance FST that contains the phone"
echo "confusions and L1 is the original lexicon."
echo ""
echo "The script assumes that L1.lex, L2.lex, words.txt and keywords.txt have"
echo "been prepared and stored in the directory <kws-data-dir>."

# K:  keywords in the bin
# L2: a lexicon that contains pronunciations of keywords in K
# E:  edit distance FST that contains the phone confusions
# L1: a lexicon that contains pronunciations of the keywords in the cache (common for a recording)

# We hope to find which "cached word" is hit by the bin
# TODO: may consider inter-bin confusion, i.e., bigram bin, in the future

########################################
# step1: collect the cached words for each recording (collect all the words on the sausages)
# step2: generate pronunciation for the cached words, via lexicon or g2p
# step3: generate L1
# Note: For L1, I should create a big L1 from lexicon.txt and words in clats. And take subset for each recording.

# step4: generate E or E' from the counts

# step5: generate prounciation L1 for each sausage bin, similar to step123

# step6: compose K x L2 x E x L1'
# step7: enhance this bin by inserting the new but cached words
# step8: specify the scores of the new sausage links
########################################

data=std2006_dev
data=std2006_eval
data=callhome_dev

nbest_dir=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/nbest_kaldi/
nbest_dir=/export/fs04/a12/rhuang/kws/kws-release/exp/$data/nbest_espnet0.8/
kws_data_dir=/export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_$data
# keywords=/export/fs04/a12/rhuang/kws/kws/data0/$data/kws/keywords.$data.txt     # std2006
keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt  # callhome
scale=1.0
nsize=50
lats_dir=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_${data}_${scale}_${nsize}

########################################
# step1
########################################

# Example:
# KW-00323 george 
# 
# en_4315_0B_00027  ,842,1,KW-00323,KW-00323,4.08,4.81,4.09,4.82,1,YES,CORR
# en_4315_0B_00035  ,846,1,KW-00323,KW-00323,0.12,0.37,0.03,0.37,0.997655,YES,CORR
# en_4576_0A_00219  ,2192,1,KW-00323,KW-00323,,,1.64,1.96,0.0222211,NO,CORR!DET
# en_4315_0B_00011  ,833,1,KW-00323,KW-00323,0.39,0.67,,,,,MISS
#
# en_4315_0B_00011 you know like george he has a little list and i have to bring for him and his wife and his kids and i have to bring for
# en_4315_0B_00027 get them yet and i have to get stuff at the wiz for menash for george
# en_4315_0B_00035 and george said no i want some back and i bought two extras and they just let me go

ls $lats_dir/clat_eps2/clat.*.eps2.gz

recording_id=en_4315_0B
job_id=5
clat=/export/fs04/a12/rhuang/kws/kws-release/test/lats_dir_1.0_50_topk/clat_eps2/clat.${job_id}.eps2.gz

zcat $clat | grep $recording_id | \
  awk '{$1=""}1' | head
# This will only print the line with recording id

# Same results:
# zcat $clat | grep $recording_id | wc
# zcat $clat | awk -v recording_id="$recording_id" '{if ($0 ~ recording_id) {print;} else {;}}' | wc

recording_id=en_4315_0B
zcat $clat | \
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
    sed '/^[[:space:]]*$/d' | sed -r '/^.{,3}$/d' | sed -r '/^\[.*\]$/d' | sed '/\[/d' | sed '/\]/d' | sed -r '/^.*\-$/d' | sed -r '/^<.*>$/d' |  \
    sort | uniq -c | sort -r \
> test/confusion/freq.txt

# https://stackoverflow.com/questions/5410757/how-to-delete-from-a-text-file-all-lines-that-contain-a-specific-string
# sed '/pattern to match/d'

zcat $clat | grep $recording_id  | wc
cat a.txt | grep $recording_id  | wc

# check pattern/substring matching
zcat $clat | \
    awk 'BEGIN {flag=0; } {
        if ($0 ~ recording_id) {
            print;
        }
    }'

# check lengths
zcat $clat | head -50 | \
    awk 'BEGIN {flag=0; } {
        print length($0)", "$0
    } END {print "flag="flag;}'

awk 'length>3' file

########################################
# step2
########################################

freq=test/confusion/freq.txt

cat $freq | awk '{print $2}' | head

# g2p example
g2p=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
g2p_nbest=10
g2p_mass=0.95
script=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/local/apply_g2p.sh
$script --nj 1 --cmd run.pl --var-counts $g2p_nbest --var-mass $g2p_mass \
  <(cat $freq | awk '{print $2}' | head -3) $g2p test/confusion/oov_results
####

lexicon=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/dict/lexicon.txt
lexiconp=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/local/dict/lexiconp.txt
comm -23 \
  <(cat $freq | awk '{print $2}' | sort -u) \
  <(cat $lexiconp | awk '{print $1}' | sort -u) \
> test/confusion/words_g2p.txt

comm -12 \
  <(cat $freq | awk '{print $2}' | sort -u) \
  <(cat $lexiconp | awk '{print $1}' | sort -u) \
> test/confusion/words_lexicon.txt

wc test/confusion/words_g2p.txt test/confusion/words_lexicon.txt

# pronunciation from g2p
g2p=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
g2p_nbest=10
g2p_mass=0.95
script=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/local/apply_g2p.sh
$script --nj 6 --cmd run.pl --var-counts $g2p_nbest --var-mass $g2p_mass \
  <(cat test/confusion/words_g2p.txt) $g2p test/confusion/words_g2p

wc test/confusion/words_g2p.txt test/confusion/words_g2p/lexicon.lex

# pronunciation from lexicon
join -j 1 <(sort test/confusion/words_lexicon.txt) <(sort $lexiconp) > test/confusion/words_lexicon.lex

# merge the two lexicons
cat test/confusion/words_lexicon.lex test/confusion/words_g2p/lexicon.lex \
  > test/confusion/L1.lex
wc test/confusion/L1.lex

########################################
# step3
########################################

# https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5c/local/datasets/extra_kws.sh
# https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5b/local/generate_proxy_keywords.sh

wdir=test/confusion
L1_lex=test/confusion/L1.lex
L2_lex=

kaldi_asr=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
oldlang=${kaldi_asr}/data/lang_sw1_fsh_fg

# create our new words.txt
cat <(awk '{print $1;}' $oldlang/words.txt) <(awk '{print $1;}' $L1_lex) | \
 sort -u | comm -23 - <(awk '{print $1;}' $oldlang/words.txt | sort -u) \
> $wdir/new_words.txt
cp $oldlang/words.txt $wdir/words.txt
word_id=`tail -n1 $oldlang/words.txt | awk '{print $2;}'`
word_id=$(($word_id+1))
cat $wdir/new_words.txt | \
  awk -v word_id="$word_id" '{print $0 " " word_id; word_id += 1;}' >> $wdir/words.txt

phone_start=3
pron_probs_param="--pron-probs";

ndisambig=`utils/add_lex_disambig.pl \
  $pron_probs_param $L1_lex $wdir/L1_disambig.lex`
ndisambig=$[$ndisambig+1]; # add one disambig symbol for silence in lexicon FST.
( for n in `seq 0 $ndisambig`; do echo '#'$n; done ) > $wdir/disambig.txt

cat $L1_lex $L2_lex |\
  awk '{for(i='$phone_start'; i <= NF; i++) {print $i;}}' |\
  sort -u | sed '1i\<eps>' |\
  cat - $wdir/disambig.txt | awk 'BEGIN{x=0} {print $0"\t"x; x++;}' \
  > $wdir/phones.txt

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

# TODO: take a subset of L1.fst

########################################
# step4
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
# step5
########################################



########################################
# step6
########################################

