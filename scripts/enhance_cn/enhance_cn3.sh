########################################
# We can compute the pair-wise phonetic edit distance between
# L2_lex and L1_lex.
# Then we will know which are the cached words that are phonetically similar
# Note, in our use case, L2 (words in a bin) is a subset of L1 (words in the recording)
########################################

python=/export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet_gpu/bin/python
script=/export/fs04/a12/rhuang/kws/kws-release/scripts/enhance_cn/get_proxies.py

recording_id=en_4315_0B

wdir=test/confusion
L1_lex=$wdir/L1_${recording_id}.lex
keywords_text=$wdir/bin_words_${recording_id}.txt
confusion=$wdir/confusionp.txt

$python $script \
  --l1_lexiconp $L1_lex \
  --l2_words <(cat $keywords_text | awk '{print $2}') \
  --phones_txt $wdir/phones.txt \
  --topk 10 \
  --confusion $confusion \
> $wdir/bin_words_${recording_id}.proxies.txt
wc $wdir/bin_words_${recording_id}.proxies.txt

cat $wdir/bin_words_${recording_id}.proxies.txt |\
  awk '{if ($2 > 0.75) {print $0;}}' \
> $wdir/bin_words_${recording_id}.proxies.filtered.txt