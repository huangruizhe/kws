# /export/fs04/a12/rhuang/log/bash_history_backup_20221016_2144.log
# 2020-08-04:00:41:46 b16 /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5
# L2_lex

cd /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5

g2p=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/1155system/exp/g2p/
g2p_nbest=10
g2p_mass=0.95
local/apply_g2p.sh --nj 1 --cmd run.pl --var-counts $g2p_nbest --var-mass $g2p_mass \
  <() $g2p local/kws/example/oov

