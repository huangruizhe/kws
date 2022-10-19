#!/bin/bash

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
. ./path.sh

vi cmd.sh
cmd_backend='local'  # Now, local runs faster than sge

# Install k2 and so on

base=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/

# Be careful to use the same bpe_model and tokens as the pretrained ESPNET model!
bpe_model=/export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet/lib/python3.8/site-packages/espnet_model_zoo/ea87bab99ecb436fc99a1a326dd0fe7b/data/token_list/bpe_unigram2000/bpe.model
dict=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm3/bpe_id.txt
tokens=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm3/tokens.txt
# text=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/train.txt

# choose your own path
decode_graph_dir=${base}/data/token_list/bpe_unigram2000/lm5/
mkdir -p ${decode_graph_dir}
lm_dir=${decode_graph_dir}

text_swbd_fisher=${lm_dir}/swbd+fisher.txt
text_swbd=${lm_dir}/swbd.txt
text_fisher=${lm_dir}/fisher.txt
text_dev=${lm_dir}/dev.txt
cut -f 2- -d " " /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/lm_train.txt > ${text_swbd_fisher}
cut -f 2- -d " " /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/train_nodup/text > ${text_swbd}
cut -f 2- -d " " /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/train_fisher/text > ${text_fisher}
cut -f 2- -d " " /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/dump/raw/train_dev/text > ${text_dev}

# Encode training text for BPE LM
# text_bpe=${decode_graph_dir}/train.bpe.txt
# spm_encode --model=${bpe_model} --output_format=piece < ${text} > ${text_bpe}
for input_text in ${text_swbd_fisher} ${text_swbd} ${text_fisher} ${text_dev}; do
    spm_encode --model=${bpe_model} --output_format=piece < ${input_text} > ${input_text%.*}.bpe.txt 
done

# Train ngram LM
# https://github.com/kaldi-asr/kaldi/blob/master/egs/swbd/s5c/local/swbd1_train_lms.sh
bpe_ngram_order=2
bpe_ngram_order=3
bpe_ngram_order=4
bpe_ngram_order=5
bpe_ngram_order=6
# bpe_lm="${lm_dir}/lm_${bpe_ngram_order}.arpa"
# echo "LM: ${bpe_lm}"
# time python local/make_kn_lm.py -ngram-order ${bpe_ngram_order} \
#   -text ${text_bpe} -lm ${bpe_lm}
# head ${bpe_lm}
for bpe_ngram_order in 2 3 4 5 6; do
    date

    echo "Computing ${bpe_ngram_order}-gram model for ${text_swbd_fisher%.*}.bpe.txt"
    python local/make_kn_lm.py -ngram-order ${bpe_ngram_order} \
        -text ${text_swbd_fisher%.*}.bpe.txt -lm ${lm_dir}/swbd+fisher_${bpe_ngram_order}.arpa
    
    echo "Computing ${bpe_ngram_order}-gram model for ${text_swbd%.*}.bpe.txt"
    python local/make_kn_lm.py -ngram-order ${bpe_ngram_order} \
        -text ${text_swbd%.*}.bpe.txt -lm ${lm_dir}/swbd_${bpe_ngram_order}.arpa
    echo "Computing ${bpe_ngram_order}-gram model for ${text_fisher%.*}.bpe.txt"
    python local/make_kn_lm.py -ngram-order ${bpe_ngram_order} \
        -text ${text_fisher%.*}.bpe.txt -lm ${lm_dir}/fisher_${bpe_ngram_order}.arpa
    
    ngram -unk -lm ${lm_dir}/swbd_${bpe_ngram_order}.arpa -ppl ${text_dev%.*}.bpe.txt -debug 2 \
        > ${lm_dir}/swbd_${bpe_ngram_order}.ppl2
    ngram -unk -lm ${lm_dir}/fisher_${bpe_ngram_order}.arpa -ppl ${text_dev%.*}.bpe.txt -debug 2 \
        > ${lm_dir}/fisher_${bpe_ngram_order}.ppl2
    compute-best-mix ${lm_dir}/swbd_${bpe_ngram_order}.ppl2 \
        ${lm_dir}/fisher_${bpe_ngram_order}.ppl2 > ${lm_dir}/sw1_fsh_mix.${bpe_ngram_order}gram.log

    grep 'best lambda' ${lm_dir}/sw1_fsh_mix.${bpe_ngram_order}gram.log | perl -e '
      $_=<>;
      s/.*\(//; s/\).*//;
      @A = split;
      die "Expecting 2 numbers; found: $_" if(@A!=2);
      print "$A[0]\n$A[1]\n";' > ${lm_dir}/sw1_fsh_mix.${bpe_ngram_order}gram.weights
    swb1_weight=$(head -1 ${lm_dir}/sw1_fsh_mix.${bpe_ngram_order}gram.weights)
    fisher_weight=$(tail -n 1 ${lm_dir}/sw1_fsh_mix.${bpe_ngram_order}gram.weights)

    echo "Computing mixture of ${lm_dir}/swbd_${bpe_ngram_order}.arpa (x $swb1_weight) and ${lm_dir}/fisher_${bpe_ngram_order}.arpa"
    ngram -order ${bpe_ngram_order} -lm ${lm_dir}/swbd_${bpe_ngram_order}.arpa -lambda $swb1_weight \
      -mix-lm ${lm_dir}/fisher_${bpe_ngram_order}.arpa \
      -unk -write-lm ${lm_dir}/swbd+fisher_${bpe_ngram_order}.mix.arpa
    
    for mdl in ${lm_dir}/*_${bpe_ngram_order}*.arpa; do
        echo $mdl
        ngram -unk -lm $mdl -ppl ${text_dev%.*}.bpe.txt
    done
done


# dev
dev_text=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/dev.txt
cat dump/raw/train_dev/text | cut -d' ' -f2- > ${dev_text}
dev_bpe=${decode_graph_dir}/dev.bpe.txt
spm_encode --model=${bpe_model} --output_format=piece < ${dev_text} > ${dev_bpe}
for bpe_ngram_order in 2 3 4 5 6; do
    bpe_lm="${lm_dir}/lm_${bpe_ngram_order}.arpa"
    ngram -order ${bpe_ngram_order} -lm ${bpe_lm} -unk -map-unk "<unk>" -ppl ${dev_bpe}
done

# prune
threshold=1.25e-7   # starting point
threshold=2e-9
bpe_ngram_order=3
# in=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm4//lm_${bpe_ngram_order}.arpa
# out=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm4//lm_${bpe_ngram_order}.${threshold}.arpa
in=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm5//swbd+fisher_3.mix.arpa
out=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm5//swbd+fisher_3.mix.prune${threshold}.arpa
in=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm5//swbd+fisher_4.mix.arpa
out=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm5//swbd+fisher_4.mix.prune${threshold}.arpa
time ngram -unk -map-unk "<unk>" \
 -order ${bpe_ngram_order} \
 -prune ${threshold} \
 -lm ${in} \
 -write-lm ${out}
head ${out}
echo "LM: ${out}"
ngram -order ${bpe_ngram_order} -lm ${out} -unk -map-unk "<unk>" -ppl ${text_dev%.*}.bpe.txt
ngram -unk -lm ${out} -ppl ${text_dev%.*}.bpe.txt

for lm in ${lm_dir}/lm_${bpe_ngram_order}*.arpa; do
    echo "LM: ${lm}"
    ngram -order ${bpe_ngram_order} -lm ${lm} -unk -map-unk "<unk>" -ppl ${dev_bpe}
done

# best:
# 3gram:
# LM: /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm4//lm_3.1e-6.arpa
# file /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm4//dev.bpe.txt: 3998 sentences, 65585 words, 0 OOVs
# 0 zeroprobs, logprob= -116313.7 ppl= 46.9442 ppl1= 59.3581
# 4gram:
# LM: /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm4//lm_4.8e-8.arpa
# file /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm4//dev.bpe.txt: 3998 sentences, 65585 words, 0 OOVs
# 0 zeroprobs, logprob= -118399.7 ppl= 50.29921 ppl1= 63.86851
# 5gram:
# LM: /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm4//lm_5.2e-8.arpa
# file /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm4//dev.bpe.txt: 3998 sentences, 65585 words, 0 OOVs
# 0 zeroprobs, logprob= -118368.2 ppl= 50.24668 ppl1= 63.79773
# 6gram:

# Create symbol table and P.fst
if [ ! -f $lm_dir/isymb.txt ]; then
    cp $dict $lm_dir/isymb.txt
    nsymb=$(tail -1 $lm_dir/isymb.txt | awk '{print $2}')
    let nsymb=nsymb+1  # Add 1 for disambiguation symbol #0
    echo "#0 $nsymb" >> $lm_dir/isymb.txt
fi 
bpe_lm=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm5//swbd+fisher_3.mix.prune2e-8.arpa
bpe_lm=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm5//swbd+fisher_4.mix.prune1e-8.arpa
bpe_lm=$(realpath $bpe_lm)
python -m kaldilm --disambig-symbol="#0" --read-symbol-table=$lm_dir/isymb.txt \
    --max-order=${bpe_ngram_order} ${bpe_lm} > ${bpe_lm%.*}.P_fst.txt
wc -l ${bpe_lm%.*}.P_fst.txt

# Run k2 decoder
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
inference_tag="decode_TP_2_3gram"
inference_tag+=".swbd+fisher_3.mix.prune2e-8"

# vi ./conf/decode_asr_transformer_with_k2_TP.yaml

# stop_stage=12
stop_stage=13
test_set=eval2000
test_set=std2006_dev
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config ./conf/decode_asr_transformer_with_k2_TP.yaml

# re-do scoring
expdir="exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/"
rm -r ${expdir}/decode_${test_set}/score_wer/scoring


exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave//decode_testtesttest/eval2000/score_wer/scoring/

decode_testtesttest/eval2000/hyp.ctm.filt.sys


lm_weights="0 0.1 0.2 0.4 0.6"
lm_weights="0 0.1 0.4 0.6"
blank_biases="-0.5 -0.2 0 0.1 0.3"
blank_biases="0 0.1 0.2"
for lm_weight in $lm_weights; do
    for blank_bias in $blank_biases; do
        echo "$(date) lm_weight: ${lm_weight}, blank_bias: ${blank_bias}"
        python /export/fs04/a12/rhuang/kws/kws/update_yaml.py --lm-weight ${lm_weight} --blank-bias ${blank_bias} --out conf/decode_asr_transformer_with_k2.yaml
        cat conf/decode_asr_transformer_with_k2.yaml

        inference_tag="decode_TP_1_3gram"
        inference_tag+=".swbd+fisher_3.mix.prune2e-8_bw${blank_bias}_lmwt${lm_weight}"

        stop_stage=13
        test_set=eval2000
        bash run.sh --test_sets "$test_set" \
            --skip_data_prep true --skip_train true \
            --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
            --stop_stage ${stop_stage} \
            --use_k2 true --use_nbest_rescoring false \
            --inference_tag ${inference_tag}
    done
done


################################################################
# Prepare lexicon L.fst
################################################################


lang_dir="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang30k"
words="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt"  # 30277

lang_dir="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang241k"
words="/export/fs04/a12/rhuang/opensat/kaldi/egs/opensat20/s5/data/lang_nosp_241k/words.txt"  # 241181

lang_dir="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang_train"
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang_train/words.txt"

lang_dir="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang_train_large"
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang_train_large/words.txt"

mkdir -p $lang_dir

# Oh, we should either:
# (1) get the words.txt from training data
# (3) get the words from other-sources but filter out the words that won't make sense to the model
echo "<eps> 0" > ${words}

# train
cat /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/train.txt | \
    tr ' ' '\n' | sort -u | awk '{print $0 " " NR+1}' >> ${words}

# train_lrage
cat /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm5/swbd.txt \
    /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm5/fisher.txt | \
    tr ' ' '\n' | sort -u | awk '{print $0 " " NR+1}' >> ${words}

# other
cp $words ${lang_dir}/words.txt

cp /export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet/lib/python3.8/site-packages/espnet_model_zoo/ea87bab99ecb436fc99a1a326dd0fe7b/data/token_list/bpe_unigram2000/bpe.model ${lang_dir}/.
cp /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm3/bpe_id.txt ${lang_dir}/.

# make to lower case:
# excluded = ["<eps>", "!SIL", "<SPOKEN_NOISE>", "<UNK>", "#0", "<s>", "</s>"]
# lexicon.append(("<UNK>", [sp.id_to_piece(sp.unk_id())]))
vi local/prepare_lang_bpe.py

# We need to clean the 

if [ ! -f $lang_dir/L_disambig.pt ]; then
    cd /export/fs04/a12/rhuang/icefall/egs/librispeech/ASR
    python local/prepare_lang_bpe.py --lang-dir $lang_dir
    cd -
fi

ls $lang_dir

# Run k2 decoder
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
inference_tag="decode_TL_large_2"
inference_tag+=""

lm_weight=0.2
blank_bias=-0.2
python /export/fs04/a12/rhuang/kws/kws/update_yaml.py --lm-weight ${lm_weight} --blank-bias ${blank_bias} --out conf/decode_asr_transformer_with_k2_TL.yaml
# vi ./conf/decode_asr_transformer_with_k2_TL.yaml

inference_tag+="_bw${blank_bias}_lmwt${lm_weight}"

# stop_stage=12
stop_stage=13
test_set=eval2000
test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config ./conf/decode_asr_transformer_with_k2_TL.yaml


################################################################
# Prepare lexicon G.fst
################################################################

lm_dir=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large/
mkdir -p ${lm_dir}

text_swbd_fisher=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm5/swbd+fisher.txt
text_swbd=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm5/swbd.txt
text_fisher=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm5/fisher.txt
text_dev=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lm5/dev.txt

for n in 2 3 4; do
    date

    echo "Computing ${n}-gram model for ${text_swbd_fisher}"
    # python local/make_kn_lm.py -ngram-order ${n} \
    #     -text ${text_swbd_fisher} -lm ${lm_dir}/swbd+fisher_${n}.arpa
    # SRILM
    ngram-count -text ${text_swbd_fisher} -order $n \
        -unk -map-unk "<unk>" -kndiscount -interpolate \
        -lm ${lm_dir}/swbd+fisher_${n}.arpa
    
    echo "Computing ${n}-gram model for ${text_swbd}"
    # python local/make_kn_lm.py -ngram-order ${n} \
    #     -text ${text_swbd} -lm ${lm_dir}/swbd_${n}.arpa
    # SRILM
    ngram-count -text ${text_swbd} -order $n \
        -unk -map-unk "<unk>" -kndiscount -interpolate \
        -lm ${lm_dir}/swbd_${n}.arpa
    echo "Computing ${n}-gram model for ${text_fisher}"
    # python local/make_kn_lm.py -ngram-order ${n} \
    #     -text ${text_fisher} -lm ${lm_dir}/fisher_${n}.arpa
    # SRILM
    ngram-count -text ${text_fisher} -order $n \
        -unk -map-unk "<unk>" -kndiscount -interpolate \
        -lm ${lm_dir}/fisher_${n}.arpa
    
    ngram -unk -lm ${lm_dir}/swbd_${n}.arpa -ppl ${text_dev} -debug 2 \
        > ${lm_dir}/swbd_${n}.ppl2
    ngram -unk -lm ${lm_dir}/fisher_${n}.arpa -ppl ${text_dev} -debug 2 \
        > ${lm_dir}/fisher_${n}.ppl2
    compute-best-mix ${lm_dir}/swbd_${n}.ppl2 \
        ${lm_dir}/fisher_${n}.ppl2 > ${lm_dir}/sw1_fsh_mix.${n}gram.log

    grep 'best lambda' ${lm_dir}/sw1_fsh_mix.${n}gram.log | perl -e '
      $_=<>;
      s/.*\(//; s/\).*//;
      @A = split;
      die "Expecting 2 numbers; found: $_" if(@A!=2);
      print "$A[0]\n$A[1]\n";' > ${lm_dir}/sw1_fsh_mix.${n}gram.weights
    swb1_weight=$(head -1 ${lm_dir}/sw1_fsh_mix.${n}gram.weights)
    fisher_weight=$(tail -n 1 ${lm_dir}/sw1_fsh_mix.${n}gram.weights)

    echo "Computing mixture of ${lm_dir}/swbd_${n}.arpa (x $swb1_weight) and ${lm_dir}/fisher_${n}.arpa"
    ngram -order ${n} -lm ${lm_dir}/swbd_${n}.arpa -lambda $swb1_weight \
      -mix-lm ${lm_dir}/fisher_${n}.arpa \
      -unk -write-lm ${lm_dir}/swbd+fisher_${n}.mix.arpa
    
    for mdl in ${lm_dir}/*_${n}*.arpa; do
        echo $mdl
        ngram -unk -lm $mdl -ppl ${text_dev}
    done
done

# prune
threshold=1e-10   # starting point
ngram_order=4
in=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large//swbd+fisher_4.mix.arpa
out=${in%.*}.prune${threshold}.arpa
time ngram -unk -map-unk "<unk>" \
 -order ${ngram_order} \
 -prune ${threshold} \
 -lm ${in} \
 -write-lm ${out}
head ${out}
echo "LM: ${out}"
ngram -order ${ngram_order} -lm ${out} -unk -map-unk "<unk>" -ppl ${text_dev}
wc -l ${out}

words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang_train/words.txt"
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang_train_large/words.txt"

# Create symbol table and G.fst
if [ ! -f $lm_dir/isymb.txt ]; then
    cp $words $lm_dir/isymb.txt
    nsymb=$(tail -1 $lm_dir/isymb.txt | awk '{print $2}')
    let nsymb=nsymb+1  # Add 1 for disambiguation symbol #0
    echo "#0 $nsymb" >> $lm_dir/isymb.txt
fi 
lm=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large//swbd+fisher_2.mix.arpa
n=2
lm=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large//swbd+fisher_3.mix.arpa
n=3
lm=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large//swbd+fisher_4.mix.arpa
lm=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/word_lm_large//swbd+fisher_4.mix.prune4e-9.arpa
n=4
lm=$(realpath $lm)
python -m kaldilm --disambig-symbol="#0" --read-symbol-table=$lm_dir/isymb.txt \
    --max-order=${n} ${lm} > ${lm%.*}.G_fst.txt
wc -l ${lm%.*}.G_fst.txt

# Run k2 decoder
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
inference_tag="decode_TLG4_large_1"
inference_tag="decode_TLG3_large_3"
inference_tag="decode_TLG2_large_2"

lm_weight=0.2
blank_bias=-0.2
python /export/fs04/a12/rhuang/kws/kws/local/update_yaml.py --lm-weight ${lm_weight} --blank-bias ${blank_bias} --out conf/decode_asr_transformer_with_k2_TLG.yaml
# vi ./conf/decode_asr_transformer_with_k2_TL.yaml

inference_tag+="_bw${blank_bias}_lmwt${lm_weight}"
inference_tag+="_nbest_scale0.5"

# stop_stage=12
stop_stage=13
test_set=eval2000
test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config ./conf/decode_asr_transformer_with_k2_TLG.yaml \
    --inference_args "--nbest 100" \
    --ngpu 0

# /export/fs04/a12/rhuang/kws/kws/local/score_kaldi_light.sh
ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_std2006_dev_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
hyp=exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_1_bw-0.2_lmwt0.2/std2006_dev/text
data=data/std2006_dev/
decode=exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_1_bw-0.2_lmwt0.2/std2006_dev/

test_set=std2006_dev
test_set=callhome_dev
ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${test_set}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
data=data/${test_set}/
decode=exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_1_bw-0.2_lmwt0.2/${test_set}/
hyp=$decode/text

bash local/score_kaldi_light.sh $ref $hyp $data $decode


################################
# Use dev data properly
################################


