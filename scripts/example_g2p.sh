#!/usr/bin/env bash

# /Users/huangruizhe/Codes/opensat2020/src/opensat2020/vocab/run.sh

infile=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_200k.txt
outfile=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_200k_prefiltered.txt
python3 pre_filter.py $infile $outfile

wc -l $infile
wc -l $outfile
comm -3 $infile $outfile


infile=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_200k_prefiltered.txt
outfile=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_200k_prefiltered_post.txt
python3 post_process.py $infile $outfile | sort > opensat/irregular.txt

v1_0=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_id_125k.txt
v1=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_125k.txt
cut -d " " -f 1 ${v1_0} > $v1

#### union

v1=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_125k.txt
v2=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_200k_prefiltered_post.txt
v3=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_merged.txt
python3 merge_vocab.py $v1 $v2 $v3

sort $v3 > $v3.sort

#### diff

v1=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_125k.txt
v2=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_200k_prefiltered_post.txt
v3=/Users/huangruizhe/Downloads/PycharmProjects/mdi_adapt/src/mdi/exp_interspeech/opensat2020/vocab/opensat/words_new.txt
python3 get_new_vocab.py $v1 $v2 $v3

sort $v3 > $v3.sort


# cf:
# https://github.com/kaldi-asr/kaldi/blob/48d2115e4bc6f1815186cd86095ee5d7b852d267/egs/hub4_english/s5/local/prepare_dict.sh
# https://github.com/kaldi-asr/kaldi/blob/48d2115e4bc6f1815186cd86095ee5d7b852d267/egs/wsj/s5/steps/dict/train_g2p.sh
lexicon=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/data/local/dict_nosp/lexicon.txt
sil=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/data/local/dict_nosp/silence_phones.txt
steps/dict/train_g2p.sh --cmd "$train_cmd" \
      --silence-phones $sil \
      $lexicon exp/g2p

oovlist=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/exp/g2p/new_data/words_new.txt
steps/dict/apply_g2p.sh --cmd "$train_cmd" --nj 16 \
    $oovlist exp/g2p exp/g2p/oov_lex
  cat exp/g2p/oov_lex/lexicon.lex | cut -f 1,3 | awk '{if (NF > 1) print $0}' > \
    exp/g2p/dict.oovs_g2p

# cf:
# https://github.com/kaldi-asr/kaldi/blob/master/egs/tedlium/s5_r2_wsj/local/prepare_dict.sh#L183-L197
dir=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/exp/g2p/dict
cat exp/g2p/oov_lex/lexicon.lex | cut -f 1,3 | awk '{if (NF > 1) print $0}' > $dir/dict.oovs_g2p

lexicon=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/data/local/dict_nosp/lexicon.txt
cat $lexicon $dir/dict.oovs_g2p | sort | uniq > $dir/lexicon.txt || exit 1;





cd /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5
# bash local/kws/run_kws.sh

data=meta_dexp/safet_hub4_bugfixed/data/safe_t_dev1_norm
lang=meta_dexp/safet_hub4_bugfixed/data/lang_test
output=meta_dexp/safet_hub4_bugfixed/data/safe_t_dev1_norm/kws

model_dir=meta_dexp/safet_hub4_bugfixed/exp/tri5b
ali_output_dir=meta_dexp/safet_hub4_bugfixed/exp/tri5b_ali_$(basename $data)
if [ $stage -le 2 ] ; then
    steps/align_fmllr.sh --nj 5 --cmd "$cmd" \
      $data $lang $model_dir $ali_output_dir

    local/kws/create_hitlist.sh $data $lang meta_dexp/safet_hub4_bugfixed/data/local/lang \
      $ali_output_dir $output
fi


meta_dexp=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/

ali-to-phones $meta_dexp/safet_hub4_bugfixed/exp/tri5b_ali_safe_t_dev1_norm/final.mdl \
  "ark:gunzip -c $meta_dexp/safet_hub4_bugfixed/exp/tri5b_ali_safe_t_dev1_norm/ali.*.gz|" ark,t:- | \
  phones-to-prons $meta_dexp/safet_hub4_bugfixed/data/lang_test/L_align.fst 178 179 \
  ark:- "ark,s:utils/sym2int.pl -f 2- --map-oov '<UNK>' $meta_dexp/safet_hub4_bugfixed/data/lang_test/words.txt <$meta_dexp/safet_hub4_bugfixed/data/safe_t_dev1_norm/text2|" ark,t:-