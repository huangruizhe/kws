# https://github.com/kaldi-asr/kaldi/blob/master/egs/babel/s5b/local/generate_confusion_matrix.sh
# https://github.com/kaldi-asr/kaldi/blob/master/egs/wsj/s5/utils/lang/make_phone_bigram_lang.sh

########################
# Demonstrate usage
########################

data=callhome_dev

kaldi_asr=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/
oldlang=${kaldi_asr}/data/lang_sw1_fsh_fg

ali_modeldir=${kaldi_asr}/exp/tri3
ali_model=$ali_modeldir/final.mdl
decocde_modeldir=${kaldi_asr}/exp/chain/tdnn7r_sp/
decode_model=$decocde_modeldir/final.mdl

alidir=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/exp/tri3_ali_1bestespnet_topk_callhome_dev
latdir=${modeldir}/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/

data_dir=data/callhome_dev_1bestespnet_topk/

wdir=test/confusion
mkdir -p $wdir
cat $oldlang/phones.txt | sed 's/_[B|E|I|S]//g' |\
  sed 's/_[%|"]//g' | sed 's/_[0-9]\+//g' > $wdir/phones.txt

acwt=0.1

cd $kaldi_asr
. ./path.sh

compute-wer --text --mode=all \
ark:<( \
  ali-to-phones  $ali_model ark:"gunzip -c $alidir/ali.1.gz|" ark,t:- |\
  int2sym.pl -f 2- $wdir/phones.txt - ) \
ark:<( \
  lattice-to-phone-lattice $decode_model ark:"gunzip -c $latdir/lat.1.gz|"  ark:- | \
  lattice-best-path --acoustic-scale=$acwt  ark:- ark,t:- ark:/dev/null | \
  int2sym.pl -f 2- $wdir/phones.txt - ) \
$wdir/confusions.1.txt

########################
# Generate a confusion matrix
########################

# option1
# cmd=run.pl
# [[ -z "$nj" ]] && [[ -f $ali/num_jobs ]] && nj=`cat $nbest_dir/num_jobs`  # kaldi
# $cmd JOB=1:$nj $wdir/log/ali_to_phones.JOB.log \
#   compute-wer --text --mode=all \
#     ark:\<\( \
#       ali-to-phones  $ali_model ark:"gunzip -c $alidir/ali.JOB.gz|" ark,t:- \|\
#       int2sym.pl -f 2- $wdir/phones.txt - \) \
#     ark:\<\( \
#       lattice-to-phone-lattice $decocde_modeld ark:"gunzip -c $latdir/lat.JOB.gz|"  ark:- \| \
#       lattice-best-path --acoustic-scale=$acwt  ark:- ark,t:- ark:/dev/null \| \
#       int2sym.pl -f 2- $wdir/phones.txt - \) \
#     $wdir/confusions.JOB.txt

# option2
compute-wer --text --mode=all \
  ark:<( \
    ali-to-phones  $ali_model ark:"gunzip -c $alidir/ali.*.gz|" ark,t:- |\
    int2sym.pl -f 2- $wdir/phones.txt - ) \
  ark:<( \
    lattice-to-phone-lattice $decode_model ark:"gunzip -c $latdir/lat.*.gz|"  ark:- | \
    lattice-best-path --acoustic-scale=$acwt  ark:- ark,t:- ark:/dev/null | \
    int2sym.pl -f 2- $wdir/phones.txt - ) \
  $wdir/confusions.1.txt

echo "Converting statistics..."
confusion_files=$wdir/confusions.1.txt
cat $confusion_files | sort | uniq -c | grep -v -E '<oov>|<sss>|<vns>|SIL' | \
  perl -ane '
    if ($F[1] eq "correct") {
      die "Unknown format " . join(" ", @F) . "\n" if ($#F != 2);
      print "$F[2] $F[2] $F[0]\n";
    } elsif ($F[1] eq "deletion" ) {
      die "Unknown format " . join(" ", @F) . "\n" if ($#F != 2);
      print "$F[2] <eps> $F[0]\n";
    } elsif ($F[1] eq "insertion") {
      die "Unknown format " . join(" ", @F) . "\n" if ($#F != 2);
      print "<eps> $F[2] $F[0]\n";
    } elsif ($F[1] eq "substitution") {
      die "Unknown format " . join(" ", @F) . "\n" if ($#F != 3);
      print "$F[2] $F[3] $F[0]\n";
    } else {
      die "Unknown line " . join(" ", @F). "\n";
    }' > $wdir/confusions.txt

cat $kwsdatadir/phones.txt |\
  grep -v -E "<.*>" | grep -v "SIL" | awk '{print $1;}' |\
  local/build_edit_distance_fst.pl --boundary-off=true \
  $confusion_matrix_param - - |\
  fstcompile --isymbols=$kwsdatadir/phones.txt \
  --osymbols=$kwsdatadir/phones.txt - $kwsdatadir/E.fst

# option3
# cmd=run.pl
# $cmd JOB=1:1 $wdir/log/ali_to_phones.JOB.log \
#   compute-wer --text --mode=all\
#     ark:\<\( \
#       ali-to-phones  $ali_model ark:"gunzip -c $alidir/ali.*.gz|" ark,t:- \|\
#       int2sym.pl -f 2- $wdir/phones.txt - \) \
#     ark:\<\( \
#       lattice-to-phone-lattice $decode_model ark:"gunzip -c $latdir/lat.*.gz|"  ark:- \| \
#       lattice-best-path --acoustic-scale=$acwt  ark:- ark,t:- ark:/dev/null \| \
#       int2sym.pl -f 2- $wdir/phones.txt - \) \
#     $wdir/confusions.JOB.txt

# It seems compute-wer does not take the third argument: $wdir/confusions.JOB.txt
# Yeah, check this commit:
# https://github.com/kaldi-asr/kaldi/blob/1a586a5d051ee145e222bb7b3e7ae1a2e838e751/src/bin/compute-wer.cc

cd /export/fs04/a12/rhuang
mkdir kaldi_2
cd kaldi_2
git clone git@github.com:kaldi-asr/kaldi.git
cd kaldi
git co 1a586a5d051ee145e222bb7b3e7ae1a2e838e751

cd tools/
make -j8
cd ../src
# ... failed!

# /Users/huangruizhe/Codes/siamese/kaldi/generate_cn.sh
# modify kaldi's source files:
vi ../../../src/kwsbin/lattice-to-kws-index.cc
# line: 190
vi ../../../src/kws/kws-functions.cc
# line: 219

cd ../../../src/kwsbin; make -j 32
cd -
cd ../../../src/kws/; make -j 32
cd -


ls /export/fs04/a12/rhuang/kaldi_2/kaldi/src/bin/compute-wer.cc
which compute-wer
cd /export/fs04/a12/rhuang/kaldi_latest/kaldi//src/bin/
cp /export/fs04/a12/rhuang/kaldi_2/kaldi/src/bin/compute-wer.cc .
make

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c

########################
# 
########################

