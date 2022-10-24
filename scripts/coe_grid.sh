cd /home/hltcoe/rhuang/espnet/egs2/swbd/asr1
f=dump/fbank_pitch/callhome_dev/feats.scp
f=dump/fbank_pitch/callhome_dev/cmvn.scp
cp $f $f.backup
sed -i 's/\/export\/fs04\/a12\/rhuang\/espnet\/egs2\/swbd\/asr1\//\/home\/hltcoe\/rhuang\/espnet\/egs2\/swbd\/asr1\//g' $f

cd /home/hltcoe/rhuang/espnet/egs2/swbd/asr1
for data in eval2000 std2006_dev std2006_eval callhome_eval; do
    for fn in feats.scp cmvn.scp; do
        f=dump/fbank_pitch/$data/$fn
        if [[ -f $f ]]; then
            cp $f $f.backup
            sed -i 's/\/export\/fs04\/a12\/rhuang\/espnet\/egs2\/swbd\/asr1\//\/home\/hltcoe\/rhuang\/espnet\/egs2\/swbd\/asr1\//g' $f
        fi
    done
done

clsp=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
scp -r rhuang@login.clsp.jhu.edu:$clsp/data/en_token_list/ data/.

clsp=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/
scp -r rhuang@login.clsp.jhu.edu:$clsp/dump/fbank_pitch/eval2000 dump/fbank_pitch/.

d1=/export/fs04/a12/rhuang/kws/kws-release/exp/
d2="."

mkdir test
d1="/export/fs04/a12/rhuang/kws/kws-release/test/kws_data_dir_*"
d2="test/."
scp -r rhuang@login.clsp.jhu.edu:$d1 $d2

data=std2006_dev
data=std2006_eval
d1=/export/fs04/a12/rhuang/kws/kws/data0/$data/kws/keywords.$data.txt
data=callhome_dev
data=callhome_eval
d1=/export/fs04/a12/rhuang/kws/kws/data/${data}/kws/queries/keywords.txt
d2=test/keywords/.
# ls test/keywords/
# keywords.callhome_dev.txt  keywords.callhome_eval.txt  keywords.std2006_dev.txt  keywords.std2006_eval.txt

for f in src/bin/compute-wer.cc src/kws/kws-functions.cc src/kws/kws-functions2.cc src/kws/kws-scoring.cc src/kwsbin/lattice-to-kws-index.cc; do
    d1=/export/fs04/a12/rhuang/kaldi_latest/kaldi/$f 
    d2=/home/hltcoe/rhuang/kaldi/$f 
    scp -r rhuang@login.clsp.jhu.edu:$d1 $d2
done

cd /home/hltcoe/rhuang/kws_exp/shay/s5c
kaldi_path=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
dd=data/std2006_eval
scp -r rhuang@login.clsp.jhu.edu:$kaldi_path/$dd $dd

for data in eval2000 std2006_dev std2006_eval callhome_dev callhome_eval; do
    d1=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/$data/text.$data.cleaned
    d2=data/$data/text.std2006_eval.cleaned
    scp -r rhuang@login.clsp.jhu.edu:$d1 $d2
done

scp -r rhuang@login.clsp.jhu.edu:/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/test/ /home/hltcoe/rhuang/kws_exp/shay/s5c


for f in cmd.sh conf data exp path.sh run*.sh steps utils; do
    d2=$f
    d1=/export/fs04/a12/rhuang/kws/kws/$d2
    scp rhuang@login.clsp.jhu.edu:$d1 $d2
done

scp -r rhuang@login.clsp.jhu.edu:/export/fs04/a12/rhuang/kaldi_ruizhe/kaldi/egs/std2006/s5/local /export/fs04/a12/rhuang/kws/kws/.

cd /home/hltcoe/rhuang/espnet/egs2/swbd/asr1
mkdir refs
for data in eval2000 std2006_dev std2006_eval callhome_dev callhome_eval; do
    d1=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/scoring_kaldi/test_filt.txt
    d2=refs/$data.test_filt.txt
    scp rhuang@login.clsp.jhu.edu:$d1 $d2
done

for data in eval2000 std2006_dev std2006_eval callhome_dev callhome_eval; do
    d1=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr1/data/$data
    d2=/home/hltcoe/rhuang/espnet/egs2/swbd/asr1/data/.
    scp -r rhuang@login.clsp.jhu.edu:$d1 $d2
done

d1=/export/fs04/a12/rhuang/kaldi_ruizhe/kaldi/egs/std2006/s5/local/score_kaldi_light.sh
d2=/home/hltcoe/rhuang/espnet/egs2/swbd/asr1/local/.
scp -r rhuang@login.clsp.jhu.edu:$d1 $d2

scp -r rhuang@login.clsp.jhu.edu:/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/local/wer_output_filter