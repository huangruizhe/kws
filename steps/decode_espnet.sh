

################################################
# run Roshan's latest swbd pretrained model
# https://huggingface.co/espnet/roshansh_asr_base_sp_conformer_swbd
################################################

# Table 1: Datasets Statistics

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1

# first go to "espnet2/bin/asr_inference.py" to modify about "token_list"
bash run.sh --skip_data_prep true \
    --skip_train true \
    --download_model espnet/roshansh_asr_base_sp_conformer_swbd \
    --stop_stage 12

# debugged for 5 hours to finally being able to run the model

# make features
utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/std2006_dev/ data/std2006_dev
utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/std2006_eval/ data/std2006_eval
# d=train; utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/callhome_${d} data/callhome_${d}
d=dev; utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/callhome_${d} data/callhome_${d}
d=eval; utils/copy_data_dir.sh /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/callhome_${d} data/callhome_${d}

# for callhome path
cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
ln -s /export/corpora5/LDC/LDC97S42/ .

vi run.sh
# set the following:
test_sets="std2006_dev std2006_eval callhome_dev callhome_eval"
# modify "Stage 3" in asr.sh to skip train_set, valid_set
# then run:
bash run.sh --skip_data_prep false \
    --skip_train true \
    --download_model espnet/roshansh_asr_base_sp_conformer_swbd \
    --stage 3 \
    --stop_stage 3

# decoding
# To save time, it is better to run each dataset on one machine
pretrained="espnet/roshansh_asr_base_sp_conformer_swbd"
test_set=
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --stop_stage 12 # --gpu_inference true

decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/$data/

# scoring
test_sets="std2006_dev std2006_eval"
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --stage 13 --stop_stage 13

# get nbest
n=100
test_sets=std2006_dev
test_sets=std2006_eval
test_sets=callhome_dev
test_sets=callhome_eval
bash run.sh --download_model $pretrained \
    --test_sets "$test_sets" --skip_data_prep true --skip_train true \
    --inference_args "--nbest $n" --stop_stage 12

# get WER
data=$test_sets
ref=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
datadir=data/${data}/
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
hyp=$decode/text
bash local/score_kaldi_light.sh $ref $hyp $datadir $decode

# run without transformer lm
# edit run.sh to use "inference_config=conf/decode_asr_nolm.yaml"
inference_tag="decode_asr_nbest100_valid.loss.best_asr_model_valid.acc.ave_withoutlm"
test_sets=eval2000
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --inference_tag ${inference_tag} \
    --stop_stage 12

# run ctc decoding
# edit run.sh to use "inference_config=conf/decode_asr_ctc.yaml"
inference_tag="decode_asr_nbest100_valid.loss.best_asr_model_valid.acc.ave_ctc"
test_sets=eval2000
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --inference_tag ${inference_tag} \
    --stop_stage 12


# scoring
test_sets=eval2000
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --inference_tag ${inference_tag} \
    --stage 13 --stop_stage 13


# decode with larger beam size
pretrained="espnet/roshansh_asr_base_sp_conformer_swbd"
test_set=
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model $pretrained \
    --stop_stage 12 \
    --inference_config "conf/decode_asr_beam40.yaml"

decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/$data/

# get nbest
n=100
test_sets=$data
bash run.sh --download_model $pretrained \
    --test_sets "$test_sets" --skip_data_prep true --skip_train true \
    --inference_args "--nbest $n" --stop_stage 12 \
    --inference_config "conf/decode_asr_beam40.yaml"
