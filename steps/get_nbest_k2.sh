#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0





#!/bin/bash

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
. ./path.sh
conda activate espnet_gpu

# Install icefall
# https://icefall.readthedocs.io/en/latest/installation/index.html
icefall=/export/fs04/a12/rhuang/icefall/
export PYTHONPATH=$icefall:$PYTHONPATH

# To enable SRILM
cd /export/fs04/a12/rhuang/kws/kws; . ./path.sh; cd -

############################################################
# Prepare the tokens, words and so on

sha256sum /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/en_token_list/bpe_unigram2000/bpe.model
# check that this matches the one from the web
# https://huggingface.co/espnet/roshansh_asr_base_sp_conformer_swbd/blob/main/ocean/projects/iri120008p/roshansh/espnet-2021/espnet-how2/egs2/swbd/asr1/data/token_list/bpe_unigram2000/bpe.model
# SHA256: 64fc45f09987e5a45cb11b6c4fce5b032c2a8479420367081b523af78d840b22
bpe_model="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/en_token_list/bpe_unigram2000/bpe.model"

# run the decoder to get the token list
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
mkdir -p /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/token_list/bpe_unigram2000/lm/
bash run.sh --skip_data_prep true \
    --skip_train true \
    --download_model espnet/roshansh_asr_base_sp_conformer_swbd \
    --stop_stage 12
tokens="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/token_list/bpe_unigram2000/lm/tokens.txt"

# We can take the same words
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/token_list/bpe_unigram2000/lm/words.txt"
cp "/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/token_list/bpe_unigram2000/lang_train_large/words.txt" $words

mkdir -p data/lang_bpe_2000_large/text
cp /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/lang_bpe_2000_large/text/{swbd+fisher,swbd,fisher,dev}.txt data/lang_bpe_2000_large/text/.

############################################################
# Define constants
lang_dir=data/lang_bpe_2000_large

# bpe_model="/export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet/lib/python3.8/site-packages/espnet_model_zoo/ea87bab99ecb436fc99a1a326dd0fe7b/data/token_list/bpe_unigram2000/bpe.model"
bpe_model="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/en_token_list/bpe_unigram2000/bpe.model"
tokens="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/token_list/bpe_unigram2000/lm/tokens.txt"
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/token_list/bpe_unigram2000/lm/words.txt"
wc $tokens $words

text_swbd_fisher=${lang_dir}/text/swbd+fisher.txt
text_swbd=${lang_dir}/text/swbd.txt
text_fisher=${lang_dir}/text/fisher.txt
text_dev=${lang_dir}/text/dev.txt
############################################################


log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

# https://github.com/k2-fsa/icefall/blob/master/egs/librispeech/ASR/prepare.sh
if [ $stage -le 6 ] && [ $stop_stage -ge 6 ]; then
  log "Stage 6: Prepare BPE based lang"

  # https://github.com/k2-fsa/icefall/blob/master/egs/librispeech/ASR/local/prepare_lang_bpe.py
  mkdir -p $lang_dir

  cp $bpe_model $lang_dir/bpe.model
  cp $words $lang_dir/words.txt
  cp $tokens $lang_dir/tokens.txt

  if [ ! -f $lang_dir/L_disambig.pt ]; then
    # This script has been modified to solve the imcompatibility between icefall/k2 vs. espnet
    script=$icefall/egs/librispeech/ASR/local/prepare_lang_bpe.py
    python $script --lang-dir $lang_dir

    # If you have this error:
    # AttributeError: module 'distutils' has no attribute 'version'
    # You need to downgrade the setuptools and then it works.
    # conda install setuptools=58.2.0
    # https://github.com/facebookresearch/detectron2/issues/3811
  fi
fi

if [ $stage -le 7 ] && [ $stop_stage -ge 7 ]; then
    log "Stage 7: Prepare bigram P"

    # Prepare text
    mkdir ${lang_dir}/text/
    cut -f 2- -d " " /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/lm_train.txt > ${text_swbd_fisher}
    cut -f 2- -d " " /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/train_nodup/text > ${text_swbd}
    cut -f 2- -d " " /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/train_fisher/text > ${text_fisher}
    cut -f 2- -d " " /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/dump/raw/train_dev/text > ${text_dev}

    # Encode word-level training text to BPE-level for training BPE LM
    for input_text in ${text_swbd_fisher} ${text_swbd} ${text_fisher} ${text_dev}; do
        echo "Encoding training text $input_text for BPE LM ..."
        spm_encode --model=${lang_dir}/bpe.model --output_format=piece < ${input_text} > ${input_text%.*}.bpe.txt 
    done

    lm_dir=${lang_dir}/text/bpe/
    mkdir $lm_dir
    (
        for bpe_ngram_order in 2 3 4 5; do
            date

            echo "Computing ${bpe_ngram_order}-gram model for ${text_swbd_fisher%.*}.bpe.txt"
            time python local/make_kn_lm.py -ngram-order ${bpe_ngram_order} \
                -text ${text_swbd_fisher%.*}.bpe.txt -lm ${lm_dir}/swbd+fisher_${bpe_ngram_order}.arpa
            # SRILM
            # ngram-count -text ${text_swbd_fisher%.*}.bpe.txt -order ${bpe_ngram_order} \
            #     -unk -map-unk "<unk>" -kndiscount -interpolate \
            #     -lm ${lm_dir}/swbd+fisher_${bpe_ngram_order}.arpa
            echo "Computing ${bpe_ngram_order}-gram model for ${text_swbd%.*}.bpe.txt"
            time python local/make_kn_lm.py -ngram-order ${bpe_ngram_order} \
                -text ${text_swbd%.*}.bpe.txt -lm ${lm_dir}/swbd_${bpe_ngram_order}.arpa
            # SRILM
            # ngram-count -text ${text_swbd%.*}.bpe.txt -order ${bpe_ngram_order} \
            #     -unk -map-unk "<unk>" -kndiscount -interpolate \
            #     -lm ${lm_dir}/swbd_${bpe_ngram_order}.arpa
            echo "Computing ${bpe_ngram_order}-gram model for ${text_fisher%.*}.bpe.txt"
            time python local/make_kn_lm.py -ngram-order ${bpe_ngram_order} \
                -text ${text_fisher%.*}.bpe.txt -lm ${lm_dir}/fisher_${bpe_ngram_order}.arpa
            # SRILM
            # ngram-count -text ${text_fisher%.*}.bpe.txt -order ${bpe_ngram_order} \
            #     -unk -map-unk "<unk>" -kndiscount -interpolate \
            #     -lm ${lm_dir}/fisher_${bpe_ngram_order}.arpa
            
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
    ) | tee $lm_dir/results.txt

    # To prune the model, refer to: run_k2_decode.sh

    # choose the best model and convert it to fst format
    best_P_model=
    order=
    cp $best_P_model $lang_dir/P.arpa

    if [ ! -f $lang_dir/P.fst.txt ]; then
      python3 -m kaldilm \
        --read-symbol-table="$lang_dir/tokens.txt" \
        --disambig-symbol='#0' \
        --max-order=$order \
        $lang_dir/P.arpa > $lang_dir/P.fst.txt
    fi
fi


if [ $stage -le 8 ] && [ $stop_stage -ge 8 ]; then
    log "Stage 8: Prepare G"
    # We assume you have install kaldilm, if not, please install
    # it using: pip install kaldilm

    lm_dir=${lang_dir}/text/word/
    mkdir -p $lm_dir

    cut -d' ' -f1 ${lang_dir}/lexicon.txt > $lm_dir/wordlist
    cp $words $lm_dir/isymb.txt

    (
        for n in 2 3 4; do
            date

            echo "Computing ${n}-gram model for ${text_swbd_fisher}"
            # python local/make_kn_lm.py -ngram-order ${n} \
            #     -text ${text_swbd_fisher} -lm ${lm_dir}/swbd+fisher_${n}.arpa
            # SRILM
            time ngram-count -text ${text_swbd_fisher} -order $n \
                -unk -map-unk "<unk>" -kndiscount -interpolate \
                -limit-vocab -vocab ${lm_dir}/wordlist \
                -lm ${lm_dir}/swbd+fisher_${n}.arpa
            
            echo "Computing ${n}-gram model for ${text_swbd}"
            # python local/make_kn_lm.py -ngram-order ${n} \
            #     -text ${text_swbd} -lm ${lm_dir}/swbd_${n}.arpa
            # SRILM
            time ngram-count -text ${text_swbd} -order $n \
                -unk -map-unk "<unk>" -kndiscount -interpolate \
                -limit-vocab -vocab ${lm_dir}/wordlist \
                -lm ${lm_dir}/swbd_${n}.arpa
            echo "Computing ${n}-gram model for ${text_fisher}"
            # python local/make_kn_lm.py -ngram-order ${n} \
            #     -text ${text_fisher} -lm ${lm_dir}/fisher_${n}.arpa
            # SRILM
            time ngram-count -text ${text_fisher} -order $n \
                -unk -map-unk "<unk>" -kndiscount -interpolate \
                -limit-vocab -vocab ${lm_dir}/wordlist \
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
                realpath $mdl
                ngram -unk -lm $mdl -ppl ${text_dev}
            done
        done
    ) | tee $lm_dir/results.txt

    # Prune the model
    threshold=5e-9   # starting point
    ngram_order=4
    in=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/lang_bpe_2000_241k/text/word/swbd+fisher_4.mix.arpa
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

    if grep -q "#0" $lang_dir/words.txt; then 
        true
    else
        echo "Insert #0 to $lang_dir/words.txt"
        cp $lang_dir/words.txt $lang_dir/words.txt.old
        nsymb=$(tail -1 $lm_dir/isymb.txt | awk '{print $2}')
        let nsymb=nsymb+1  # Add 1 for disambiguation symbol #0
        echo "#0 $nsymb" >> $lang_dir/words.txt
    fi

    best_G_model=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/lang_bpe_2000_large/text/word/swbd+fisher_4.mix.prune4e-9.arpa
    best_G_model=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/lang_bpe_2000_241k/text/word/swbd+fisher_4.mix.prune5e-9.arpa
    order=4

    python3 -m kaldilm \
        --read-symbol-table=$lang_dir/words.txt \
        --disambig-symbol='#0' \
        --max-order=$order \
        ${best_G_model} > $lang_dir/G_${order}_gram.fst.txt
    ln -s $(realpath $lang_dir/G_${order}_gram.fst.txt) $lang_dir/G.fst.txt
fi

if [ $stage -le 9 ] && [ $stop_stage -ge 9 ]; then
    log "Stage 9: Compile HLG"
    # This script has been modified 
    script=$icefall/egs/librispeech/ASR/local/compile_hlg.py
    python $script --lang-dir $lang_dir
fi

# Run k2 decoder
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
inference_tag="decode_TLG4_large_new1"
graph="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lang_bpe_2000_large/HLG.pt"
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lang_bpe_2000_large/words.txt"

# k2 decoding params:
lm_weight=0.6
blank_bias=-1.6
search_beam_size=20
output_beam_size=20
max_active_states=10000
min_active_states=30
# rescoring params:
am_weight=0.5
decoder_weight=1.2
nnlm_weight=0.2
ngram_weight=1.0
#
yaml=conf/decode_asr_transformer_with_k2_TLG_new_rescore.yaml
yaml=conf/decode_asr_transformer_with_k2_TLG_new_241k.yaml
yaml=conf/decode_asr_transformer_with_k2_TLG_new_temp.yaml
yaml=conf/decode_asr_transformer_with_k2_TLG_large_new1.yaml
python /export/fs04/a12/rhuang/kws/kws/local/update_yaml.py \
  --graph ${graph} --words ${words} \
  --lm-weight ${lm_weight} --blank-bias ${blank_bias} \
  --am_weight $am_weight --decoder_weight $decoder_weight --nnlm_weight $nnlm_weight --ngram_weight $ngram_weight \
  --search_beam_size $search_beam_size --output_beam_size $output_beam_size \
  --max_active_states $max_active_states --min_active_states $min_active_states \
  --out $yaml
python3 -c "from yaml import load, Loader; y=load(open('$yaml', 'r'), Loader=Loader); print(y)"
# vi $yaml

inference_tag+="_bw${blank_bias}_lmwt${lm_weight}"
inference_tag+="_rescore_a${am_weight}_d${decoder_weight}_n${nnlm_weight}_ng${ngram_weight}"
inference_tag+="_sb${search_beam_size}_ob${output_beam_size}_max${max_active_states}_min${min_active_states}"
# inference_tag+="_nbest_scale0.5"
echo $inference_tag
echo $test_set

test_set=eval2000
test_set=std2006_dev
test_set=eval2000_small
test_set=train_dev

# stop_stage=12
stop_stage=13

bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "espnet/roshansh_asr_base_sp_conformer_swbd" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config $yaml \
    --inference_args "--nbest 100" \
    --ngpu 0


# 1best
stop_stage=13
test_set=eval2000
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "espnet/roshansh_asr_base_sp_conformer_swbd" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config $yaml \
    --inference_args "--nbest 1" \
    --ngpu 0

# scoring
test_set=eval2000
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "espnet/roshansh_asr_base_sp_conformer_swbd" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config $yaml \
    --inference_args "--nbest 1" \
    --ngpu 0 --stage 13 --stop_stage 13



search_beam_size=8
output_beam_size=8
max_active_states=1000
for param in 100 500 1000 5000 10000 20000; do
    date
    max_active_states=$param
    echo "max_active_states = $max_active_states"

    yaml=conf/decode_asr_transformer_with_k2_TLG_new_temp.yaml
    python /export/fs04/a12/rhuang/kws/kws/local/update_yaml.py \
    --lm-weight ${lm_weight} --blank-bias ${blank_bias} \
    --am_weight $am_weight --decoder_weight $decoder_weight --nnlm_weight $nnlm_weight \
    --search_beam_size $search_beam_size --output_beam_size $output_beam_size \
    --max_active_states $max_active_states \
    --out $yaml

    inference_tag="decode_TLG4_241k_new1"
    # inference_tag+="_sb${search_beam_size}_ob${output_beam_size}_max${max_active_states}_min${min_active_states}"
    inference_tag+="_sb${search_beam_size}_ob${output_beam_size}_max${max_active_states}"

    stop_stage=13
    test_set=eval2000
    bash run.sh --test_sets "$test_set" \
        --skip_data_prep true --skip_train true \
        --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
        --stop_stage ${stop_stage} \
        --use_k2 true --use_nbest_rescoring false \
        --inference_tag ${inference_tag} \
        --k2_config $yaml \
        --inference_args "--nbest 1" \
        --ngpu 0
done


# Generate the nbest list with scores for searching rescoring hyper params
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config $yaml \
    --inference_args "--nbest -100" \
    --ngpu 0


# Rescore
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring true \
    --inference_tag ${inference_tag} \
    --k2_config $yaml \
    --inference_args "--nbest 100" \
    --ngpu 0

# Rescore + gpu
# GPU Decoding seems not available -- the default swbd recipe also decoded using cpu
# 1. cuda out of memory
# 2. qsub job in state Eqw error: can't chdir to directory: No such file or directory
#
# bash run.sh --test_sets "$test_set" \
#     --skip_data_prep true --skip_train true \
#     --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
#     --stop_stage ${stop_stage} \
#     --use_k2 true --use_nbest_rescoring true \
#     --inference_tag ${inference_tag} \
#     --k2_config $yaml \
#     --inference_args "--nbest 100" \
#     --gpu_inference true \
#     --inference_nj 8

########## How to resume running a job that is killed? ##########
# check the following:
# .../logdir/q/asr_inference.sh
# .../logdir/q/asr_inference.log
qsub -v PATH -cwd -S /bin/bash -j y -l arch=*64* -o exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_new1_bw-0.2_lmwt0.2_rescore/eval2000/logdir/q/asr_inference.log \
  -q all.q -l hostname='!c12*&!b02*&!b03*&!c15*' -l mem_free=16G,ram_free=16G  -t 4:4 \
  /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_new1_bw-0.2_lmwt0.2_rescore/eval2000/logdir/q/asr_inference.sh \
  >>exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_new1_bw-0.2_lmwt0.2_rescore/eval2000/logdir/q/asr_inference.log 2>&1

qstat -j xxx | grep stdout_path_list

# Score std2006 etc output with sclite

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


############################################################
# Search for optimal decoding parameters for k2 decoding

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
inference_tag="decode_TLG4_large_new1"
graph="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lang_bpe_2000_large/HLG.pt"
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lang_bpe_2000_large/words.txt"

# k2 decoding params:
# lm_weight=0.6
# blank_bias=-0.5

graph="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lang_bpe_2000_large/HLG.pt"
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lang_bpe_2000_large/words.txt"
lm_weights="0.4 0.5 0.6 0.7 0.8"
blank_biases="-2.0 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 0"
for lm_weight in $lm_weights; do
    for blank_bias in $blank_biases; do
        echo "$(date) lm_weight: ${lm_weight}, blank_bias: ${blank_bias}"

        # inference_tag="decode_TLG4_large_new1"
        inference_tag="decode_TLG4_large_new3"  # for token-level alignment, updated the lexicon in HLG graph
        inference_tag+="_bw${blank_bias}_lmwt${lm_weight}"

        yaml=conf/${inference_tag}.yaml
        python /export/fs04/a12/rhuang/kws/kws/local/update_yaml.py \
            --graph ${graph} --words ${words} \
            --lm-weight ${lm_weight} --blank-bias ${blank_bias} \
            --out $yaml
        cat $yaml

        stop_stage=12
        test_set=eval2000

        bash run.sh --test_sets "$test_set" \
            --skip_data_prep true --skip_train true \
            --download_model "espnet/roshansh_asr_base_sp_conformer_swbd" \
            --stop_stage ${stop_stage} \
            --use_k2 true --use_nbest_rescoring false \
            --inference_tag ${inference_tag} \
            --k2_config $yaml \
            --inference_args "--nbest 1" \
            --ngpu 0 &
    done
done

# track progress
ls exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new3_bw*_lmwt*/eval2000/text

# scoring
for lm_weight in $lm_weights; do
    for blank_bias in $blank_biases; do
        echo "$(date) lm_weight: ${lm_weight}, blank_bias: ${blank_bias}"

        # inference_tag="decode_TLG4_large_new1"
        inference_tag="decode_TLG4_large_new3"  # for token-level alignment, updated the lexicon in HLG graph
        inference_tag+="_bw${blank_bias}_lmwt${lm_weight}"

        yaml=conf/${inference_tag}.yaml

        bash run.sh --test_sets "$test_set" \
            --skip_data_prep true --skip_train true \
            --download_model "espnet/roshansh_asr_base_sp_conformer_swbd" \
            --use_k2 true --use_nbest_rescoring false \
            --inference_tag ${inference_tag} \
            --k2_config $yaml \
            --inference_args "--nbest 1" \
            --ngpu 0 --stage 13 --stop_stage 13
    done
done

grep "hyp.ctm.filt.sys" exp/espnet/roshansh_asr_base_sp_conformer_swbd/RESULTS.md | cut -d'|' -f9

(
    lm_weights="0.2 0.4 0.5 0.6 0.7 0.8 0.9"
    blank_biases="-2.0 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 0"
    for lm_weight in $lm_weights; do
        for blank_bias in $blank_biases; do
            inference_tag="decode_TLG4_large_new3"
            inference_tag+="_bw${blank_bias}_lmwt${lm_weight}"

            wer=`grep -iF "$inference_tag" exp/espnet/roshansh_asr_base_sp_conformer_swbd/RESULTS.md | grep "hyp.ctm.filt.sys" | cut -d'|' -f9`
            echo $lm_weight $blank_bias $wer
        done
    done
) > k2_lm_weight+blank_bias+wer.results

# For roshan's model, the best combination of lm_weight and blank_bias is: 
# lm_weight=0.6
# blank_bias=-1.6

############################################################
# Try getting nbest results

# In theory, it should not be worse than the above WER

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
# inference_tag="decode_TLG4_large_new1"
# inference_tag="decode_TLG4_large_new2"  # for token-level alignment
inference_tag="decode_TLG4_large_new3"  # for token-level alignment, updated the lexicon in HLG graph
graph="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lang_bpe_2000_large/HLG.pt"
words="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/lang_bpe_2000_large/words.txt"

# k2 decoding params:
lm_weight=0.6
blank_bias=-1.6
search_beam_size=20
output_beam_size=20
max_active_states=10000
min_active_states=30
# rescoring params:
am_weight=0.5
decoder_weight=1.2
nnlm_weight=0.2
ngram_weight=1.0
#
yaml=conf/decode_asr_transformer_with_k2_TLG_new_rescore.yaml
yaml=conf/decode_asr_transformer_with_k2_TLG_new_241k.yaml
yaml=conf/decode_asr_transformer_with_k2_TLG_new_temp.yaml
yaml=conf/decode_asr_transformer_with_k2_TLG_large_new1.yaml
python /export/fs04/a12/rhuang/kws/kws/local/update_yaml.py \
  --graph ${graph} --words ${words} \
  --lm-weight ${lm_weight} --blank-bias ${blank_bias} \
  --am_weight $am_weight --decoder_weight $decoder_weight --nnlm_weight $nnlm_weight --ngram_weight $ngram_weight \
  --search_beam_size $search_beam_size --output_beam_size $output_beam_size \
  --max_active_states $max_active_states --min_active_states $min_active_states \
  --out $yaml
python3 -c "from yaml import load, Loader; y=load(open('$yaml', 'r'), Loader=Loader); print(y)"
# vi $yaml

inference_tag+="_bw${blank_bias}_lmwt${lm_weight}"
inference_tag+="_rescore_a${am_weight}_d${decoder_weight}_n${nnlm_weight}_ng${ngram_weight}"
inference_tag+="_sb${search_beam_size}_ob${output_beam_size}_max${max_active_states}_min${min_active_states}"
# inference_tag+="_nbest_scale0.5"
echo $inference_tag
echo $test_set

test_set=eval2000
test_set=std2006_dev
test_set=eval2000_small
test_set=train_dev

stop_stage=12
# stop_stage=13

bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "espnet/roshansh_asr_base_sp_conformer_swbd" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config $yaml \
    --inference_args "--nbest 100" \
    --ngpu 0

# tracking decoding progress:
qstat -u rhuang | wc -l
tail -n 2 exp/espnet/roshansh_asr_base_sp_conformer_swbd/${inference_tag}/$test_set/logdir/asr_inference.*.log
tail -n 6 exp/espnet/roshansh_asr_base_sp_conformer_swbd/${inference_tag}/$test_set/logdir/asr_inference.*.log | grep -C 3 batch_idx
watch -n 5 "less exp/espnet/roshansh_asr_base_sp_conformer_swbd/${inference_tag}/$test_set/logdir/asr_inference.8.log | tail -n 4"
uid=en_4910-B_014847-015376; grep $uid data/$test_set/text
wc -l exp/espnet/roshansh_asr_base_sp_conformer_swbd/${inference_tag}/$test_set/logdir/output.*/1best_recog/text
grep -iF error exp/espnet/roshansh_asr_base_sp_conformer_swbd/${inference_tag}/$test_set/logdir/asr_inference.*.log

# scoring
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "espnet/roshansh_asr_base_sp_conformer_swbd" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} \
    --k2_config $yaml \
    --inference_args "--nbest 100" \
    --ngpu 0 --stage 13 --stop_stage 13

bash local/score_one.sh exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/

# 1-best
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.callhm.ctm.filt.dtl:Percent Total Error       =   15.7%   (3388)
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.ctm.filt.dtl:Percent Total Error       =   12.4%   (5345)
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.swbd.ctm.filt.dtl:Percent Total Error       =    9.1%   (1957)

# 100-best, nbest_scale=0.8
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.callhm.ctm.filt.dtl:Percent Total Error       =   15.7%   (3391)
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.ctm.filt.dtl:Percent Total Error       =   12.5%   (5380)
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.swbd.ctm.filt.dtl:Percent Total Error       =    9.3%   (1989)
#
# logdir/asr_inference.29.log:2022-04-03 21:38:38,317 (asr_inference_k2:1488) INFO: sw_4689-B_009014-010379 has encountered errors during decoding, hyp="".
# sw_4689-B_009014-010379 and and he's the oldest and then my youngest is the si- the first grader and the little girl which are my two younger they really like to spend that time just before bed being raised and having uh

# 100-best, nbest_scale=1.0
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.callhm.ctm.filt.dtl:Percent Total Error       =   15.7%   (3388)
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.ctm.filt.dtl:Percent Total Error       =   12.5%   (5378)
# exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6//eval2000/score_wer/scoring/hyp.swbd.ctm.filt.dtl:Percent Total Error       =    9.3%   (1990)
#
# So the difference in nbest_decoding vs. one_best_decoding is due to that super long utterance

########## How to resume running a job that is killed? ##########
########## Increase memory when necessary, up to 60GB ##########
qstat -j 3293261

/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/std2006_dev/logdir/q/asr_inference.sh
qsub -v PATH -cwd -S /bin/bash -j y -l arch=*64* -o exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/std2006_dev/logdir/q/asr_inference.log -q all.q -l hostname='!c12*&!b02*&!b03*&!c15*&!b09*' -l mem_free=20G,ram_free=20G  -t 18:18 /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/std2006_dev/logdir/q/asr_inference.sh >>exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/std2006_dev/logdir/q/asr_inference.log 2>&1

/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/std2006_eval/logdir/q/asr_inference.sh
qsub -v PATH -cwd -S /bin/bash -j y -l arch=*64* -o exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/std2006_eval/logdir/q/asr_inference.log -q all.q -l hostname='!c12*&!b02*&!b03*&!c15*&!b09*' -l mem_free=20G,ram_free=20G  -t 27:27 /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/std2006_eval/logdir/q/asr_inference.sh >>exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/std2006_eval/logdir/q/asr_inference.log 2>&1


/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/callhome_dev/logdir/q/asr_inference.sh
# 16 18
for i in 16 18; do
    qsub -v PATH -cwd -S /bin/bash -j y -l arch=*64* -o exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/callhome_dev/logdir/q/asr_inference.log -l mem_free=20G,ram_free=20G -q all.q -l hostname='!c12*&!b02*&!b03*&!c15*&!b09*'  -t $i:$i /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/callhome_dev/logdir/q/asr_inference.sh >>exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/callhome_dev/logdir/q/asr_inference.log 2>&1
done

/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/callhome_eval/logdir/q/asr_inference.sh
# 9 12 19 24 30
for i in 9 12 19 24 30; do
    qsub -v PATH -cwd -S /bin/bash -j y -l arch=*64* -o exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/callhome_eval/logdir/q/asr_inference.log -q all.q -l hostname='!c12*&!b02*&!b03*&!c15*&!b09*' -l mem_free=20G,ram_free=20G  -t $i:$i /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/callhome_eval/logdir/q/asr_inference.sh >>exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new1_bw-1.6_lmwt0.6/callhome_eval/logdir/q/asr_inference.log 2>&1
done

# Need to run the rest of decoding steps to merge the outputs
# 1. Modify egs2/swbd/asr12/asr.sh, comment out the decoding codes "# 2. Submit decoding jobs"
# 2. Run decoding again


# Scoring 
test_set=std2006_dev
test_set=callhome_dev
ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${test_set}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/${inference_tag}/${test_set}/
hyp=$decode/text

bash local/score_kaldi_light.sh $ref $hyp data/${test_set}/ $decode

#####
decode=../asr12/exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_TLG4_large_1_bw-0.2_lmwt0.2/${test_set}/
#####

for i in 10 19; do
qsub -v PATH -cwd -S /bin/bash -j y -l arch=*64* -o exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new3_bw-1.6_lmwt0.6/callhome_eval/logdir/q/asr_inference.log -l mem_free=60G,ram_free=60G -q all.q -l hostname='!c12*&!b02*&!b03*&!c15*&!b09*'  -t $i:$i /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new3_bw-1.6_lmwt0.6/callhome_eval/logdir/q/asr_inference.sh >>exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_TLG4_large_new3_bw-1.6_lmwt0.6/callhome_eval/logdir/q/asr_inference.log 2>&1
done


# Scoring for kaldi
# cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
kaldi_path=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c
test_set=
ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${test_set}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
hyp=${kaldi_path}/exp/chain/tdnn7r_sp/decode_std2006_dev_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/penalty_0.0/10.txt
hyp=${kaldi_path}/exp/chain/tdnn7r_sp/decode_std2006_eval_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/penalty_0.0/11.txt
hyp=${kaldi_path}/exp/chain/tdnn7r_sp/decode_callhome_dev_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/penalty_0.0/9.txt
hyp=${kaldi_path}/exp/chain/tdnn7r_sp/decode_callhome_eval_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/penalty_0.0/10.txt
bash local/score_kaldi_light.sh $ref <(cat $hyp | local/wer_output_filter) data/${test_set}/ score_temp