#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

### Word-level alignment

# ESPNET's vocab
# --words "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large/lang/words.txt" \

# Kaldi's vocab
script="/export/fs04/a12/rhuang/kws/kws/local/k2ali2ali_word_level.py"
test_set=eval2000
test_set=std2006_dev
test_set=callhome_dev
decode=exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_new1_bw-0.2_lmwt0.2/${test_set}/
python $script \
    --tokens "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large/lang/tokens.txt" \
    --words-kaldi "/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt" \
    --words-espnet "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large/lang/words.txt" \
    --best "${decode}/logdir/output.\\*/1best_recog/text" \
    --k2-ali-files "${decode}/logdir/output.\\*/1best_recog/best_path_aux_labels" \
    > ${decode}/1best.k2.ali.txt


script="/export/fs04/a12/rhuang/kws/kws/local/k2ali2ali_word_level.py"
test_set=eval2000
test_set=std2006_dev
test_set=callhome_dev
per_frame_time=0.04
shift_nframes=20
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/${test_set}/
python $script \
    --tokens "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/token_list/bpe_unigram2000/lm/tokens.txt" \
    --words-kaldi "/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt" \
    --words-espnet "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/token_list/bpe_unigram2000/lm/words.txt" \
    --best "${decode}/logdir/output.\\*/1best_recog/text" \
    --k2-ali-files "${decode}/logdir/output.\\*/1best_recog/best_path_aux_labels" \
    --per_frame_time $per_frame_time \
    --shift_nframes $shift_nframes \
    > ${decode}/1best.k2.ali.words.txt
realpath ${decode}/1best.k2.ali.words.txt

# Get another k2 alignment based on tokens, instead of words
# 1. modify espnet2/bin/asr_inference_k2.py about "best_paths[0].tokens.tolist()"
# 2. run nbest decoding again

# Kaldi's vocab
script="/export/fs04/a12/rhuang/kws/kws/local/k2ali2ali.py"
test_set=eval2000
test_set=std2006_dev
test_set=callhome_dev
per_frame_time=0.04
shift_nframes=0
# decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new2_bw-1.6_lmwt0.6/${test_set}/
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new3_bw-1.6_lmwt0.6/${test_set}/
python $script \
    --tokens "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/token_list/bpe_unigram2000/lm/tokens.txt" \
    --words "/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt" \
    --best "${decode}/logdir/output.\\*/1best_recog/text" \
    --k2-ali-files "${decode}/logdir/output.\\*/1best_recog/best_path_aux_labels" \
    --per_frame_time $per_frame_time \
    --shift_nframes $shift_nframes \
    > ${decode}/1best.k2.ali.tokens.txt
realpath ${decode}/1best.k2.ali.tokens.txt

