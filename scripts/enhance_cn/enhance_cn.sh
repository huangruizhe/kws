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
# step3: generate L2

# step4: generate E or E' from the counts

# step5: generate prounciation for each sausage bin, similar to step123

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
> freq.txt

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
