cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr1
. ./path.sh
. ./cmd.sh

cd /export/fs04/a12/rhuang/kws/kws-release
ln -s /export/fs04/a12/rhuang/kaldi_latest/kaldi/egs/wsj/s5/utils .

text="/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/text"
workdir="workdir"
bash scripts/query_gen/run.sh --text $text --workdir $workdir --order 2 --freq-thres 2 --stage 0 --stop-stage 0
