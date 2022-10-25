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
#        We should remove some of them.
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


 
