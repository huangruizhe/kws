exp_dir=

####################################
# nbest vocab
nbest_file=/home/hltcoe/rhuang/kws-release/exp/std2006_dev_small/nbest_coe_standard/nbest/40/nbest.txt
nbest_file=temp/nbest/40/nbest.txt
cut -d" " -f3- $nbest_file | \
    tr ' ' '\n' | sort | uniq -c | sort -r | awk '{print $2" "$1}' > nbest40_vocab.txt

####################################
# training vocabulary
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
lm_text=data/lm_train.txt  # https://github.com/espnet/espnet/blob/master/egs2/swbd/asr1/local/data.sh
wc $lm_text

cat $lm_text | cut -d" " -f2- | \
    tr ' ' '\n' | sort | uniq -c | sort -r | awk '{print $2" "$1}' | sort -k1,1 > lm_vocab.txt

# TODO: we may do some filtering here
# check enhance_cn for details

####################################
# lexicon

####################################
# kw_list
data=callhome_dev
# keywords=/export/fs04/a12/rhuang/kws/kws/data0/$data/kws/keywords.$data.txt     # std2006
keywords=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt  # callhome

cat $keywords | awk '{$1=""}1' | \
    tr ' ' '\n' | sort | uniq -c | sort -r | awk '{print $2" "$1}' | sort -k1,1 > kwlist_vocab.txt

# which of the word in the kwlist is not in the lm_vocab?
f1=kwlist_vocab.txt
f2=lm_vocab.txt
join -t" " -j1 <(sort -k1,1 $f1) <(sort -k1,1 $f2) -a1 > a.txt
cat a.txt | awk "NF<3"

####################################
# Analysis

# https://stackoverflow.com/questions/13382566/left-outer-join-on-two-files-in-unix
f1=nbest40_vocab.txt
f2=lm_vocab.txt
join -t" " -j1 <(sort -k1,1 $f1) <(sort -k1,1 $f2) -a1 > a.txt
cat a.txt | awk "NF==3" | wc
wc a.txt $f1