#!/bin/bash

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/

vi cmd.sh
cmd_backend='sge'

utils/copy_data_dir.sh /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_dev/ data/std2006_dev
utils/copy_data_dir.sh /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/std2006_eval/ data/std2006_eval
d=train; utils/copy_data_dir.sh /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/callhome_${d} data/callhome_${d}
d=dev; utils/copy_data_dir.sh /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/callhome_${d} data/callhome_${d}
d=eval; utils/copy_data_dir.sh /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/callhome_${d} data/callhome_${d}

# https://github.com/espnet/espnet/blob/master/egs2/swbd/asr1/local/data.sh
# text: filter
# wav.scp: sample rate
for x in std2006_dev std2006_eval callhome_train callhome_dev callhome_eval; do
    sed -i.bak -e "s/$/ sox -R -t wav - -t wav - rate 16000 dither | /" data/${x}/wav.scp

    cp data/${x}/text data/${x}/text.org
    paste -d "" \
            <(cut -f 1 -d" " data/${x}/text.org) \
            <(awk '{$1=""; print tolower($0)}' data/${x}/text.org \
            | perl -pe 's| \(\%.*\)||g' | perl -pe 's| \<.*\>||g' \
            | sed -e "s/(//g" -e "s/)//g") \
            | sed -e 's/\s\+/ /g' > data/${x}/text.org2 # for ci check
    # remove the file with empty text, otherwise bug in stage calc perplexity 
    awk -F ' ' '{if(length($2)!=0)print $0}' data/${x}/text.org2 > data/${x}/text 

    utils/fix_data_dir.sh data/${x}
done

# feature extraction/preparation
test_sets="std2006_dev std2006_eval callhome_train callhome_dev callhome_eval"
bash run.sh --test_sets "$test_sets" \
    --stage 3 --stop_stage 3

# https://superuser.com/a/253470/1135036
for x in train dev eval; do
    cp data/callhome_$x/wav.scp data/callhome_$x/wav.scp.orig
    sed 's/ffmpeg -i pipe:0 -ar 8000 -f wav  pipe:1 |//g' data/callhome_$x/wav.scp.orig > data/callhome_$x/wav.scp
done

# decoding
# To save time, it is better to run each dataset on one machine
test_sets1="std2006_dev std2006_eval"
test_sets2="callhome_train callhome_dev callhome_eval"
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave"
# To save time, it is better to run each dataset on one machine
test_set=
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage 12 # --gpu_inference true

# scoring
test_sets="std2006_dev std2006_eval"
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stage 13 --stop_stage 13

# get nbest
n=10
bash exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/run.sh \
  --inference_args "--nbest $n"
# less exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_nbest10_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/eval2000/logdir/output.1/1best_recog/text

n=100
test_sets=callhome_dev
bash run.sh --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --test_sets "$test_sets" --skip_data_prep true --skip_train true \
    --inference_args "--nbest $n"

n=100
test_sets=std2006_dev
bash run.sh --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --test_sets "$test_sets" --skip_data_prep true --skip_train true \
    --inference_tag "decode_normal_token_scores2" \
    --inference_args "--nbest $n"

####################
# rover examples
####################
# you need to set the following ROVER parameter in the src code
# and recompile it to support more than 50 hypos
# 1. 
# #define MAX_HYPS 50
# 2.
# int nword, max_word=50, i;
# and replace every "50" with max_word if you change it to other numbers

rover -h rover_example/1.ctm ctm -h rover_example/2.ctm ctm -o rover_example/result.ctm -m oracle

# check whether the timing info affect rover alignment -- the answer is no, by default
cat rover_example/1.ctm | \
  awk '{ print $1 "\t" $2 "\t" 0 "\t" 0 "\t" $5 }' > rover_example/3.ctm
cat rover_example/2.ctm | \
  awk '{ print $1 "\t" $2 "\t" 0 "\t" 0 "\t" $5 }' > rover_example/4.ctm
rover -h rover_example/3.ctm ctm -h rover_example/4.ctm ctm -o rover_example/result2.ctm -m oracle

# with optional confidence score for each word
cat rover_example/1.ctm | \
  awk '{ print $1 "\t" $2 "\t" 0 "\t" 0 "\t" $5 "\t" 0.1}' > rover_example/5.ctm
cat rover_example/2.ctm | \
  awk '{ print $1 "\t" $2 "\t" 0 "\t" 0 "\t" $5 "\t" 0.2}' > rover_example/6.ctm
rover -h rover_example/5.ctm ctm -h rover_example/6.ctm ctm -o rover_example/result56.ctm -m oracle

# get the ctm file for rover
f=rover_example/6best.text
#  awk '{ for (i = 2; i <= NF; i++) print $1 " A 0 0 " $i }' $f > $f.ctm
awk '{
if (NF > 1)
	for (i = 2; i <= NF; i++) print $1 " A 0 0 " $i;
else
	print $1 " A 0 0 [empty]";
}' $f > $f.ctm

# get nbest for our datasets
test_sets="eval2000"
test_sets="std2006_dev std2006_eval"
test_sets="callhome_train callhome_dev callhome_eval"
n=100
bash run.sh --test_sets "$test_sets" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --inference_args "--nbest $n"

# convert nbest results to ctm
n=10
dir=exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_nbest10_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/eval2000/
tgt_dir=rover_example/eval2000/
n=100
dir=exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/eval2000/
tgt_dir=rover_example/eval2000_100/
for i in $(eval echo "{1..$n}"); do
    # echo "$i "
    f=$dir/logdir/output.10/${i}best_recog/text
    awk '{
        if (NF > 1)
            for (i = 2; i <= NF; i++) print $1 " A 0 0 " $i;
        else
            print $1 " A 0 0 [empty]";
    }' $f > $tgt_dir/$i.ctm
done

# check files exists
uid=en_4938-B_007711-007964
for i in $(eval echo "{1..$n}"); do
    f=$tgt_dir/$i.ctm
    if [ ! -f "$f" ]
    then
        echo "$f does not exist"
        break
    fi
    if grep -q $uid $f; then 
        true
    else
        echo "uid=$uid does not exist in $f"
        break
    fi
done

# this is not the best way to use ROVER, as
# ROVER assume the same utterance to appear
# in each ctm file, which is not the case
# for nbest lists as not every utterance has
# the same length of nbest list.
hypos=""
for i in $(eval echo "{1..$n}"); do
    hypos="$hypos -h $tgt_dir/$i.ctm ctm "
done
rover -m oracle $hypos -o $tgt_dir/result.ctm

# So, we have to apply ROVER utterance-by-utterance
# TODO: this can be parallelized
n=100
data=eval2000
data=std2006_dev
data=std2006_eval
data=callhome_eval
dir=exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
tgt_dir=rover_example/${data}_100/
data_dir=data/${data}
mkdir -p $tgt_dir/temp/
nj=32
segments=$data_dir/segments
utt2dur=/export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/$data_dir/utt2dur
### progress bar ###
# https://stackoverflow.com/questions/238073/how-to-add-a-progress-bar-to-a-shell-script
BAR_length=100
BAR_character='#'
BAR=$(printf %${BAR_length}s | tr ' ' $BAR_character)
work_todo=$(awk 'END { print NR }' $segments)
work_done=0
rm $tgt_dir/result.{txt,ctm}
mkdir -p $tgt_dir/temp
# for each uid in the file
while read -r line; do
    # printf 'uid: %s\n' "$line"
    rm $tgt_dir/temp/*.{ctm,txt,sco}
    # first, decide which job handled this uid
    job_id=
    for i in $(eval echo "{1..$nj}"); do
        if grep -q $line $dir/logdir/keys.${i}.scp; then 
            job_id=$i
            break
        fi
    done
    if [ -z "${job_id}" ]; then
        echo "ERROR: job_id is empty."
        break
    fi

    # loop over nbest files
    hypos=""
    for i in $(eval echo "{1..$n}"); do
        f_text=$dir/logdir/output.${job_id}/${i}best_recog/text
        f_score=$dir/logdir/output.${job_id}/${i}best_recog/score

        (exit 1);   # set the return code $?
        [[ -f $f_text ]] && grep -q $line $f_text;
        if [[ $? -eq 1 ]]; then 
            break
        fi

        grep $line $f_text | awk '{
            if (NF > 1)
                for (i = 2; i <= NF; i++) print $1 " A 0 0 " $i;
            else
                print $1 " A 0 0 [empty]";
        }' > $tgt_dir/temp/$i.ctm
        # wc -l $tgt_dir/temp/$i.ctm

        grep $line $f_text >> $tgt_dir/temp/hyp.txt
        grep $line $f_score >> $tgt_dir/temp/hyp.sco

        hypos="$hypos -h $tgt_dir/temp/$i.ctm ctm "
    done

    # this is the ctm for this uid
    rover -m oracle $hypos -o $tgt_dir/temp/result.ctm

    cat $tgt_dir/temp/result.ctm >> $tgt_dir/result.ctm
    paste <(cut -d' ' -f1 $tgt_dir/temp/hyp.sco) \
        <(cut -d' ' -f2 $tgt_dir/temp/hyp.sco | grep -Eo '[+-]?[0-9]+([.][0-9]+)?') \
        <(cut -d' ' -f2- $tgt_dir/temp/hyp.txt) >> $tgt_dir/result.txt

    # break

    # show progress
    ((work_done=work_done+1))
    # progress=$(( $work_done * $BAR_length / $work_todo ))
    # echo "${BAR:0:$progress}" "$progress/$BAR_length"   # -ne: do not output the trailing newline
    echo "uid=$line   progress: $work_done/$work_todo"
done < <(cut -d' ' -f1 $segments)
# done < <(echo "en_4938-B_007711-007964")

# be careful: ROVER can lowercase your uid
# awk '{$1=toupper($1)} 1' $tgt_dir/result.ctm > $tgt_dir/result.ctm.tmp
# This only works for eval2000
awk '{gsub(/a/, "A", $1); gsub(/b/, "B", $1)} 1' $tgt_dir/result.ctm > $tgt_dir/result.ctm.tmp
mv $tgt_dir/result.ctm.tmp $tgt_dir/result.ctm

# check the nbest result for uid
grep -h en_4938-B_007711-007964 $dir/logdir/output.10/*best_recog/text

####################
# draw a sausage
####################

# example to draw a fsa
#
# 0 1 The 1
# 1 2 person 0.5
# 1 3 people 0.5
# 2 4 is 1
# 3 4 are 1
# 4 5 mad 1
# 5
#
mkdir fstdraw/
wget -P fstdraw/ https://www.oxinabox.net/Kaldi-Notes/fst-example/simple.fsa.txt 
cut -d' ' -f1,3 fstdraw/simple.fsa.txt | awk ' { t = $1; $1 = $2; $2 = t; print; } ' > fstdraw/words.txt
# vi fstdraw/words.txt to do a bit modification
fstcompile --acceptor=true --isymbols=fstdraw/words.txt fstdraw/simple.fsa.txt > fstdraw/simple.fsa
fstdraw --acceptor=true --isymbols=fstdraw/words.txt --portrait=true fstdraw/simple.fsa | dot -Tjpg > fstdraw/simple.jpg

# convert ctm to fsa format, derive the symbol table, and draw the fsa
uid=en_4938-B_007711-007964
uid=`echo "$uid" | awk '{ print tolower($1) }'`
grep $uid $tgt_dir/result.ctm > $tgt_dir/draw.ctm
converter=/export/fs04/a12/rhuang/kws/kws/local/cmt2fsa.py 
cat $tgt_dir/draw.ctm | $converter > $tgt_dir/draw.fsa.txt
awk '{if (NF >= 3) print $3 }' $tgt_dir/draw.fsa.txt | sort -u | awk ' { print $1 " " NR } ' > $tgt_dir/words.txt
fstcompile --acceptor=true --isymbols=$tgt_dir/words.txt $tgt_dir/draw.fsa.txt > $tgt_dir/draw.fsa
fstdraw --acceptor=true --isymbols=$tgt_dir/words.txt --portrait=true $tgt_dir/draw.fsa | dot -Tps > $tgt_dir/draw.eps

####################
# convert sausage to lattice
####################

cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c

# check the lattice for an uid
uid=en_4938-B_007711-007964
grep $uid data/eval2000_hires/split50/*/segments
gunzip -c exp/chain/tdnn7r_sp/decode_eval2000_sw1_fsh_fg_rnnlm_1e_0.45/lat.12.gz | utils/int2sym.pl -f 3 data/lang/words.txt | grep en_4938-B_007711-007964
gunzip -c exp/chain/tdnn7r_sp/decode_eval2000_sw1_fsh_fg_rnnlm_1e_0.45/lat.12.gz | utils/int2sym.pl -f 3 data/lang/words.txt > rover_example/eval2000_100/lat.12.txt

# check the duration for this utterance and derive a number of frames
grep en_4938-B_007711-007964 data/eval2000/utt2dur
# number of frames for a chain model: 2.65 / 0.03 = 89
# number of frames for each bin: 5 6 5 6 5 6 5 6 5 6 5 6 5 6 6 6

script=/export/fs04/a12/rhuang/kws/kws/local/sausage_get_posterior.py
scale=1.0
scale=0.8
scale=0.5
python $script --ctm "$tgt_dir/result.ctm" \
    --txt "$tgt_dir/result.txt" \
    --dur $utt2dur \
    --scale $scale \
    > $tgt_dir/clat.$scale.txt


script=/export/fs04/a12/rhuang/kws/kws/local/sausage_get_posterior.py
scale=1.0
# scale=0.8
# scale=0.5
python $script --ctm "$tgt_dir/result.ctm.1" \
    --txt "$tgt_dir/result.txt" \
    --dur $utt2dur \
    --scale $scale \
    > $tgt_dir/clat.$scale.txt.1

# var=${var%,*}; var=${var%,*};

# draw it and check
sed 1d $tgt_dir/clat.$scale.txt | rev | cut -d',' -f3- | rev > $tgt_dir/clat.$scale.fsa
cp $tgt_dir/clat.$scale.fsa $tgt_dir/draw.fsa.txt
awk '{if (NF >= 3) print $3 }' $tgt_dir/draw.fsa.txt | sort -u | awk ' { print $1 " " NR } ' > $tgt_dir/words.txt
fstcompile --acceptor=true --isymbols=$tgt_dir/words.txt $tgt_dir/draw.fsa.txt > $tgt_dir/draw.fsa
fstdraw --acceptor=true --isymbols=$tgt_dir/words.txt --portrait=true --width=5 $tgt_dir/draw.fsa | dot -Tps > $tgt_dir/draw.eps
realpath $tgt_dir/draw.eps

# convert to kaldi's lat.gz format
utter_id=$tgt_dir/utt.map
echo "en_4938-b_007711-007964 1" > $utter_id
cat /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/$tgt_dir/clat.$scale.txt | \
    utils/sym2int.pl --map-oov "<unk>" -f 3 $tgt_dir/words.txt | \
    lattice-to-kws-index --max-states-scale=4 --allow-partial=true \
      --frame-subsampling-factor=3 \
      --max-silence-frames=50 --strict=true ark:$utter_id ark,t:- ark:- | \
      kws-index-union --skip-optimization=false --strict=true --max-states=1000000 \
      ark:- "ark,t:$tgt_dir/index.txt"
mkdir $tgt_dir/kws_indices_1
cat $tgt_dir/index.txt | gzip -c > $tgt_dir/kws_indices_1/index.1.gz

cp /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt $tgt_dir/words.txt

# said she really did not need to because she has all these newer pictures
cat > $tgt_dir/keywords.txt <<EOF
kw01 said
kw02 she
kw03 really
kw04 because
kw05 has
kw06 all
kw07 these
kw08 newer
kw09 pictures
kw010 did not
kw011 need to
kw012 because she
kw013 newer pictures
kw014 all these newer pictures
EOF
realpath $tgt_dir/keywords.txt

echo 1 > /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/rover_example/eval2000_100/kws_indices_1/num_jobs
tr '[:upper:]' '[:lower:]' < $tgt_dir/kws/utt.map > $tgt_dir/kws/temp; cp $tgt_dir/kws/temp $tgt_dir/kws/utt.map
local/kws/search.sh --cmd run.pl --min-lmwt 1 --max-lmwt 1 --indices-dir $tgt_dir/kws_indices --skip-indexing true data/lang $tgt_dir $tgt_dir



# Diagnose
# https://stackoverflow.com/questions/83329/how-can-i-extract-a-predetermined-range-of-lines-from-a-text-file-on-unix
uid=fsh_60732_exA_B_177860_179620
clat=rover_example/std2006_dev_100/temp/$uid.clat.txt
zcat kws_indices/std2006_dev_100/temp/20/clat.scale1.0.gz | head -n +150 | tail -n +85 > $clat

uid=fsh_60354_exA_A_110950_113390
clat=rover_example/std2006_dev_100/temp/$uid.clat.txt
zcat kws_indices/std2006_dev_100/temp/2/clat.scale1.0.gz | head -n +499 | tail -n +438 > $clat

uid=fsh_60386_exA_B_161810_163320
clat=rover_example/std2006_dev_100/temp/$uid.clat.txt
zcat kws_indices/std2006_dev_100/temp/4/clat.scale1.0.gz | head -n +338 | tail -n +266 > $clat

uid=fsh_60720_exA_B_166390_168020
clat=rover_example/std2006_dev_100/temp/$uid.clat.txt
zcat kws_indices/std2006_dev_100/temp/18/clat.scale1.0.gz | head -n +6768 | tail -n +6691 > $clat

# draw it and check
tgt_dir=rover_example/std2006_dev_100/
#-------
sed 1d $clat | rev | cut -d',' -f3- | rev > $clat.fsa
cp $clat.fsa $tgt_dir/draw.fsa.txt
awk '{if (NF >= 3) print $3 }' $tgt_dir/draw.fsa.txt | sort -u | awk ' { print $1 " " NR } ' > $tgt_dir/words_fsa.txt
fstcompile --acceptor=true --isymbols=$tgt_dir/words_fsa.txt $tgt_dir/draw.fsa.txt > $tgt_dir/draw.fsa
fstdraw --acceptor=true --isymbols=$tgt_dir/words_fsa.txt --portrait=true --width=5 $tgt_dir/draw.fsa | dot -Tps > $tgt_dir/draw.eps
realpath $tgt_dir/draw.eps

# convert to kaldi's lat.gz format
utter_id=$tgt_dir/utt.map
words=$tgt_dir/words.txt
data_dir=std2006_dev
#--------
cp /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/$(basename $data_dir)/kws/words.txt $words
grep -q "<unk>" run.sh || echo "<unk>" $(wc -l $words | cut -d' ' -f1) >> $words
echo "$uid 1" > $utter_id
cat $clat | \
    utils/sym2int.pl --map-oov "<unk>" -f 3 $words | \
    lattice-to-kws-index --max-states-scale=3 --allow-partial=true \
      --frame-subsampling-factor=3 --verbose=1 \
      --max-silence-frames=50 --strict=true ark:$utter_id ark,t:- ark:- | \
      kws-index-union --skip-optimization=false --strict=true --max-states=1000000 \
      ark:- "ark,t:$tgt_dir/index.txt"
# mkdir $tgt_dir/kws_indices_1
# cat $tgt_dir/index.txt | gzip -c > $tgt_dir/kws_indices_1/index.1.gz

# --verbose=1

# determinize the sausage/clat
cat $clat | utils/sym2int.pl --map-oov "<unk>" -f 3 $words | lattice-determinize ark,t:- ark:$clat.det
cat $clat.det | \
    lattice-to-kws-index --max-states-scale=4 --allow-partial=true \
      --frame-subsampling-factor=3 --verbose=1 \
      --max-silence-frames=50 --strict=true ark:$utter_id ark,t:- ark:- | \
      kws-index-union --skip-optimization=false --strict=true --max-states=1000000 \
      ark,t:- "ark,t:$tgt_dir/index.det.txt"

# visually check the index
# cat $tgt_dir/index.txt | utils/int2sym.pl -f 3 $words

# draw the index
cat $tgt_dir/index.txt | utils/int2sym.pl -f 3 $words | sed 1d - | rev | cut -d',' -f3- | rev > $tgt_dir/index.txt.fsa.txt
fstcompile --isymbols=$words --osymbols=$tgt_dir/osym.txt $tgt_dir/index.txt.fsa.txt > $tgt_dir/draw.fsa
fstdraw --isymbols=$words --osymbols=$tgt_dir/osym.txt --portrait=true --width=5 $tgt_dir/draw.fsa | dot -Tps > $tgt_dir/draw.eps
realpath $tgt_dir/draw.eps

cat > $tgt_dir/osym.txt <<EOF
0 0
1 1
2 2
3 3
4 4
5 5
EOF


# format ATWV/MTWV/OTWV/STWV
f=exp/chain/tdnn7r_sp/decode_std2006_eval_sw1_fsh_fg_rnnlm_1e_0.45//kws_2/details/score.txt
readarray -t results < <(cat $f | rev | cut -d' ' -f1 | rev); echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}
# cat $f | awk '{
# if (NR==1) 
# {
# 	atwv=$4; print "1" NR $0;
# } 
# elseif (NR==2) 
# {
# 	stwv=$4; print "2" NR $0;
# } 
# elseif (NR==3) 
# {
# 	mtwv=$4; print "3" NR $0;
# } 
# elseif (NR==5) 
# {
# 	otwv=$4; print "5" NR $0;
# }
# } END{print atwv "/" mtwv "/" otwv "/" stwv}'

data=
rm /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices/${data}_100/kws_indices_3
ln -sf /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices/${data}_100/kws_indices_2_0.8/  /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices/${data}_100/kws_indices_3
time bash local/kws/run_kws_std2006.nbest.sh --max-distance 150 \
  --keywords /export/fs04/a12/rhuang/kws/kws/data0/std2006_dev/kws/keywords.std2006_dev.txt \
  --expid 3 --stage 0 --data data/${data} \
  --output data/${data}/kws/ \
  --indices_dir /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/kws_indices/${data}_100/kws_indices \
  --system exp/chain/tdnn7r_sp/decode_${data}_sw1_fsh_fg_rnnlm_1e_0.45/



########################################################################
### k2 decoding experiments ###
########################################################################

# keep only the first 240 utterances from eval2000
utils/fix_data_dir.sh data/eval2000_small

test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --stage 3 --stop_stage 3

# run normal decoding and scoring
# decode
test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage 12 # --gpu_inference true

# check log at: exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/eval2000_small/logdir/asr_inference.*.log

# scoring
test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stage 13 --stop_stage 13

# Results:
# 2022-02-07T05:25:53 (asr.sh:1391:main) Write cer result in exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/eval2000_small/score_cer/result.txt
# |       SPKR           |       # Snt              # Wrd        |       Corr                 Sub         Del                 Ins                 Err              S.Err        |
# |       Sum/Avg        |        240                8819        |       90.8                 4.5         4.7                 4.8                14.0               64.6        |
# 2022-02-07T05:25:56 (asr.sh:1391:main) Write wer result in exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/eval2000_small/score_wer/result.txt
# |       SPKR           |       # Snt              # Wrd       |       Corr                 Sub                 Del                 Ins                Err               S.Err        |
# |       Sum/Avg        |        240                1935       |       76.9                15.2                 7.9                 3.6               26.7                64.6        |
# 2022-02-07T05:25:59 (asr.sh:1391:main) Write ter result in exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/eval2000_small/score_ter/result.txt
# |       SPKR           |       # Snt              # Wrd        |       Corr                 Sub                Del                 Ins                 Err              S.Err        |
# |       Sum/Avg        |        240                2362        |       79.1                15.2                5.7                 8.0                28.8               64.6        |



# decode with k2 option
# download config file first:
# https://github.com/espnet/espnet/blob/master/egs2/librispeech/asr1/conf/decode_asr_transformer_with_k2.yaml

bash tools/installers/install_k2.sh
# [WARNING] k2=1.10.dev20211103 requires GLIBC_2.27, but your GLIBC is 2.24. Skip k2-installation
# Then follow this: https://github.com/k2-fsa/k2/issues/854
conda install -c k2-fsa -c pytorch -c conda-forge k2=1.7 python=3.8 cudatoolkit=11.1 pytorch=1.8.1

cd egs2/swbd/asr12/

test_set=eval2000_small
test_set="eval2000 std2006_dev std2006_eval callhome_train callhome_dev callhome_eval"
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage 12 \
    --use_k2 true --use_nbest_rescoring false

# scoring
test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stage 13 --stop_stage 13 \
    --use_k2 true --use_nbest_rescoring false

# Results:
# 2022-02-07T06:11:42 (asr.sh:1391:main) Write cer result in exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_use_k2_k2_ctc_decoding_true_use_nbest_rescoring_false/eval2000_small/score_cer/result.txt
# |          SPKR              |          # Snt                    # Wrd           |          Corr                       Sub                      Del                       Ins                       Err               S.Err           |
# |          Sum/Avg           |           240                      8819           |          90.7                       4.2                      5.1                       5.5                      14.7                68.3           |
# 2022-02-07T06:11:46 (asr.sh:1391:main) Write wer result in exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_use_k2_k2_ctc_decoding_true_use_nbest_rescoring_false/eval2000_small/score_wer/result.txt
# |          SPKR              |          # Snt                    # Wrd          |          Corr                       Sub                       Del                       Ins                      Err               S.Err           |
# |          Sum/Avg           |           240                      1935          |          75.5                      16.5                       8.0                       3.9                     28.4                68.3           |
# 2022-02-07T06:11:49 (asr.sh:1391:main) Write ter result in exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_use_k2_k2_ctc_decoding_true_use_nbest_rescoring_false/eval2000_small/score_ter/result.txt
# |          SPKR              |          # Snt                    # Wrd           |          Corr                       Sub                      Del                       Ins                       Err               S.Err           |
# |          Sum/Avg           |           240                      2362           |          78.4                      15.1                      6.5                       8.6                      30.1                68.3           |

# The above k2 decoder is plain. It has only the T graph. It is essentially CTC decoding with 1best approximation.
# Now, let's get the P graph and try TP decoding, where P is a bigram or trigram of BPEs

# https://github.com/google/sentencepiece#encode-raw-text-into-sentence-piecesids
base=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
# bpe_model=${base}/data/token_list/bpe_unigram2000/bpe.model  # WRONG!!!
# tokens=${base}/data/token_list/bpe_unigram2000/tokens.txt  # WRONG!!!
bpe_model=/export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet/lib/python3.8/site-packages/espnet_model_zoo/ea87bab99ecb436fc99a1a326dd0fe7b/data/token_list/bpe_unigram2000/bpe.model
tokens=${base}/data/token_list/bpe_unigram2000/lm3/tokens.txt
# --
input=${base}/data/token_list/bpe_unigram2000/train.txt
# output=${base}/data/token_list/bpe_unigram2000/train.bpe.txt
output=${base}/data/token_list/bpe_unigram2000/lm3/train.bpe.txt
# --
input=${base}/data/token_list/bpe_unigram2000/eval2000_small.txt
cat /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/data/eval2000_small/text | cut -f 2- -d" " | sort -u > $input
output=${base}/data/token_list/bpe_unigram2000/eval2000_small.bpe.txt
# --

# dict=${base}/data/token_list/bpe_unigram2000/bpe_id.txt
dict=${base}/data/token_list/bpe_unigram2000/lm3/bpe_id.txt
spm_encode --model=${bpe_model} --output_format=piece < $input > $output
# spm_encode --model=${bpe_model} --output_format=piece < $input | \
#   tr ' ' '\n' | sort -u | awk '{print $0 " " NR+1}' >> ${dict}
cat $tokens | awk '{print $0 " " NR-1}' > ${dict}
wc -l ${dict}

# train a bigram or trigram model (arpa format)
cd /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c; . ./path.sh; cd -
vocab=${base}/data/token_list/bpe_unigram2000/tokens.txt
n=2
n=3
lm=${base}/data/token_list/bpe_unigram2000/train.${n}gram.kn.gz
lm=${base}/data/token_list/bpe_unigram2000/train.${n}gram.gt.gz
# ngram-count -text $input -vocab $vocab -lm $lm -kndiscount1 -gt1min 0 -kndiscount2 -gt2min 1 -kndiscount3 -gt3min 1 -order $n -unk -sort -map-unk "$oov_symbol"
# ngram-count -lm $tgtdir/1gram.gt0.gz -gt1min 0 -order 1 -text $train_text -vocab $tgtdir/vocab -unk -sort -map-unk "$oov_symbol"
# ngram-count -lm $tgtdir/2gram.gt01.gz -gt1min 0 -gt2min 1 -order 2 -text $train_text -vocab $tgtdir/vocab -unk -sort -map-unk "$oov_symbol"
ngram-count -gt1min 0 -gt2min 1 -gt3min 1 -no-sos -no-eos -unk -sort -map-unk "<unk>" \
  -order $n \
  -text $input -vocab $vocab  -lm $lm

# replace

ngram-count -gt1min 0 -gt2min 1 -gt3min 1 -no-sos -no-eos -unk -sort -map-unk "<unk>" \
  -order $n \
  -text $input -vocab $vocab  -write ${lm%.*}.count
ngram-count -gt1min 0 -gt2min 1 -gt3min 1 -no-sos -no-eos -unk -sort -map-unk "<unk>" \
  -order $n \
  -read ${lm%.*}.count -vocab $vocab  -lm $lm

# Prepare BPE language model (for TP decoding)
# https://github.com/desh2608/espnet/blob/mini_scale_2022/egs/mini_scale_2022/asr1/run_shared.sh
lm_dir="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lm3"
mkdir -p ${lm_dir}
bpe_ngram_order=2
bpe_ngram_order=3
bpe_lm="${lm_dir}/lm_${bpe_ngram_order}.arpa"
# text=${base}/data/token_list/bpe_unigram2000/train.bpe.txt
text=${base}/data/token_list/bpe_unigram2000/lm3/train.bpe.txt
text=${base}/data/token_list/bpe_unigram2000/eval2000_small.bpe.txt
echo "LM: ${bpe_lm}"
python local/make_kn_lm.py -ngram-order ${bpe_ngram_order} \
  -text $text -lm ${bpe_lm}
# Create symbol table
cp $dict $lm_dir/isymb.txt
nsymb=$(tail -1 $lm_dir/isymb.txt | awk '{print $2}')
# Add 1 for disambiguation symbol #0
let nsymb=nsymb+1
echo "#0 $nsymb" >> $lm_dir/isymb.txt
python -m kaldilm --disambig-symbol="#0" --read-symbol-table=$lm_dir/isymb.txt \
    --max-order=${bpe_ngram_order} ${bpe_lm} > ${lm_dir}/P_${bpe_ngram_order}.fst.txt
wc -l ${lm_dir}/P_${bpe_ngram_order}.fst.txt

# edit espnet2/bin/asr_inference_k2.py

inference_tag="decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_use_k2_k2_ctc_decoding_true_use_nbest_rescoring_false"
# inference_tag+="9_lm_0.2_blank-0.2_b40_ms10w"
inference_tag+="10_2_am_1d0.2"
# inference_tag+="8_2_am_1d0.2_blank-0.2"

# stop_stage=12
stop_stage=13
test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} 
    # --gpu_inference true
    # --inference_nj 64

# scoring
test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stage 13 --stop_stage 13 \
    --use_k2 true --use_nbest_rescoring false \
    --inference_tag ${inference_tag} 

# turn on rescoring
stop_stage=13
test_set=eval2000_small
bash run.sh --test_sets "$test_set" \
    --skip_data_prep true --skip_train true \
    --download_model "Yuekai Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave" \
    --stop_stage ${stop_stage} \
    --use_k2 true --use_nbest_rescoring true \
    --inference_tag ${inference_tag} # --gpu_inference true


expdir=exp/Yuekai_Zhang/swbd_asr_train_asr_cformer5_raw_bpe2000_sp_valid.acc.ave/
type=wer
grep -H -e Avg "${expdir}"/*/*/score_${type}/result.txt | grep ${test_set} | \
  sed -e "s#${expdir}/\([^/]*/[^/]*\)/score_${type}/result.txt:#|\1#g" | \
  sed -e 's#Sum/Avg##g' | tr '|' ' ' | tr -s ' ' '|'

# https://github.com/k2-fsa/icefall/blob/master/egs/librispeech/ASR/prepare.sh
lang_dir="/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12//data/token_list/bpe_unigram2000/lang1"
mkdir -p $lang_dir
# We reuse words.txt from phone based lexicon
# so that the two can share G.pt later.
base=/export/fs04/a12/rhuang/espnet/egs2/swbd/asr12/
# cut -d' ' -f1 ${base}/data/local/dict_nosp/lexicon.txt > ${lang_dir}/words.txt
cp /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/data/lang/words.txt ${lang_dir}/words.txt
tr '[:upper:]' '[:lower:]' < /export/fs04/a12/rhuang/icefall/egs/librispeech/ASR/data/lang_phone/words.txt > ${lang_dir}/words.txt
cp /export/fs04/a12/rhuang/anaconda/anaconda3/envs/espnet/lib/python3.8/site-packages/espnet_model_zoo/ea87bab99ecb436fc99a1a326dd0fe7b/data/token_list/bpe_unigram2000/bpe.model ${lang_dir}/.

if [ ! -f $lang_dir/L_disambig.pt ]; then
    cd /export/fs04/a12/rhuang/icefall/egs/librispeech/ASR
    python local/prepare_lang_bpe.py --lang-dir $lang_dir
fi


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
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
hyp=$decode/text
wc $ref $hyp
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
pretrained="espnet/roshansh_asr_base_sp_conformer_swbd"
inference_tag="decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.9"
bash run.sh --download_model $pretrained \
    --test_sets "$test_sets" --skip_data_prep true --skip_train true \
    --inference_args "--nbest $n" --stop_stage 12 \
    --inference_config "conf/decode_asr_beam40.yaml" \
    --inference_tag ${inference_tag}

decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam100_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam200_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}/

decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}_topk
decode=exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/${data}_stochastic

# beam200
# 2022-07-20T15:32:53 (asr.sh:1573:main) Successfully finished. [elapsed=11816s]


%WER 10.86 [ 3729 / 34324, 665 ins, 1142 del, 1922 sub ]
%SER 40.74 [ 1680 / 4124 ]
Scored 4124 sentences, 0 not present in hyp.
Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.8/std2006_dev//scoring_kaldi/

%WER 10.85 [ 3723 / 34324, 663 ins, 1135 del, 1925 sub ]
%SER 40.69 [ 1678 / 4124 ]
Scored 4124 sentences, 0 not present in hyp.
Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.6/std2006_dev//scoring_kaldi/

%WER 10.86 [ 3729 / 34324, 665 ins, 1142 del, 1922 sub ]
%SER 40.74 [ 1680 / 4124 ]
Scored 4124 sentences, 0 not present in hyp.
Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/std2006_dev_topk/scoring_kaldi/

%WER 10.85 [ 3723 / 34324, 663 ins, 1135 del, 1925 sub ]
%SER 40.69 [ 1678 / 4124 ]
Scored 4124 sentences, 0 not present in hyp.
Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave/std2006_dev_stochastic/scoring_kaldi/


# Stochastic beam search
n=100
test_sets=$data
pretrained="espnet/roshansh_asr_base_sp_conformer_swbd"
temperature=9.0
inference_tag="decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic${temperature}"
bash run.sh --download_model $pretrained \
    --test_sets "$test_sets" --skip_data_prep true --skip_train true \
    --inference_args "--nbest $n --temperature $temperature" --stop_stage 12 \
    --inference_config "conf/decode_asr_beam40.yaml" \
    --inference_tag ${inference_tag} &

# 0.0 Successfully finished. [elapsed=7117s]
# %WER 325.56 [ 136718 / 41995, 95142 ins, 5893 del, 35683 sub ] [PARTIAL]
# %SER 99.97 [ 6409 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.0/callhome_dev//scoring_kaldi/

# 0.01
# %WER 100.89 [ 42367 / 41995, 749 ins, 37404 del, 4214 sub ] [PARTIAL]
# %SER 94.07 [ 6031 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.01/callhome_dev//scoring_kaldi/

# 0.05
# %WER 97.04 [ 40751 / 41995, 1378 ins, 27363 del, 12010 sub ] [PARTIAL]
# %SER 93.43 [ 5990 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.05/callhome_dev//scoring_kaldi/

# 0.1
# %WER 85.13 [ 35752 / 41995, 3108 ins, 18071 del, 14573 sub ] [PARTIAL]
# %SER 91.67 [ 5877 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.1/callhome_dev//scoring_kaldi/
# 0.0435/0.0435/0.0956/0.1501
# There are several 1best hypothesis failed to get alignment from kaldi

# 0.2
# %WER 32.76 [ 13757 / 41995, 2419 ins, 4619 del, 6719 sub ] [PARTIAL]
# %SER 72.39 [ 4641 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.2/callhome_dev//scoring_kaldi/
# 0.4585/0.4585/0.5154/0.6068
# There are several 1best hypothesis failed to get alignment from kaldi

# 0.3
# %WER 21.30 [ 8945 / 41995, 1430 ins, 2855 del, 4660 sub ] [PARTIAL]
# %SER 54.14 [ 3471 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.3/callhome_dev//scoring_kaldi/
# 0.7046/0.7055/0.7338/0.7480
# There are several 1best hypothesis failed to get alignment from kaldi

# 0.4
# %WER 20.40 [ 8566 / 41995, 1312 ins, 2716 del, 4538 sub ] [PARTIAL]
# %SER 52.82 [ 3386 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.4/callhome_dev//scoring_kaldi/
# 0.7455/0.7478/0.7782/0.7927
# There are several 1best hypothesis failed to get alignment from kaldi

# 0.5
# %WER 20.26 [ 8507 / 41995, 1266 ins, 2786 del, 4455 sub ] [PARTIAL]
# %SER 52.64 [ 3375 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.5/callhome_dev//scoring_kaldi/
# 0.7614/0.7627/0.7963/0.8110

# 0.6
# %WER 20.19 [ 8478 / 41995, 1239 ins, 2783 del, 4456 sub ] [PARTIAL]
# %SER 52.61 [ 3373 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.6/callhome_dev//scoring_kaldi/
# 0.7666/0.7693/0.8094/0.8251

# 0.7
# %WER 20.18 [ 8476 / 41995, 1252 ins, 2765 del, 4459 sub ] [PARTIAL]
# %SER 52.68 [ 3377 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.7/callhome_dev//scoring_kaldi/
# 0.7695/0.7716/0.8139/0.8298

# 0.8
# %WER 20.22 [ 8492 / 41995, 1227 ins, 2837 del, 4428 sub ] [PARTIAL]
# %SER 52.66 [ 3376 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.8/callhome_dev//scoring_kaldi/
# 0.7741/0.7756/0.8185/0.8353

# 0.9
# %WER 20.16 [ 8466 / 41995, 1223 ins, 2814 del, 4429 sub ] [PARTIAL]
# %SER 52.69 [ 3378 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic0.9/callhome_dev//scoring_kaldi/
# 0.7703/0.7719/0.8155/0.8318

# 1.0
# %WER 20.21 [ 8486 / 41995, 1229 ins, 2814 del, 4443 sub ] [PARTIAL]
# %SER 52.71 [ 3379 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic1.0/callhome_dev//scoring_kaldi/
# 0.7761/0.7767/0.8222/0.8408

# 1.5
# %WER 20.20 [ 8482 / 41995, 1214 ins, 2837 del, 4431 sub ] [PARTIAL]
# %SER 52.68 [ 3377 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic1.5/callhome_dev//scoring_kaldi/
# 0.7726/0.7745/0.8191/0.8377

# 2.0
# %WER 20.18 [ 8473 / 41995, 1212 ins, 2827 del, 4434 sub ] [PARTIAL]
# %SER 52.68 [ 3377 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic2.0/callhome_dev//scoring_kaldi/
# 0.7761/0.7767/0.8222/0.8408

# 3.0
# %WER 20.21 [ 8487 / 41995, 1215 ins, 2842 del, 4430 sub ] [PARTIAL]
# %SER 52.68 [ 3377 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic3.0/callhome_dev//scoring_kaldi/
# 0.7767/0.7781/0.8232/0.8416

# 5.0
# %WER 20.35 [ 8545 / 41995, 1285 ins, 2813 del, 4447 sub ] [PARTIAL]
# %SER 52.99 [ 3397 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic5.0/callhome_dev//scoring_kaldi/
# 0.7762/0.7762/0.8230/0.8420
# There are several 1best hypothesis failed to get alignment from kaldi

# 6.0
# %WER 21.23 [ 8915 / 41995, 1597 ins, 2804 del, 4514 sub ] [PARTIAL]
# %SER 54.33 [ 3483 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic6.0/callhome_dev//scoring_kaldi/
# 0.7730/0.7733/0.8197/0.8425
# There are several 1best hypothesis failed to get alignment from kaldi

# 7.0
# %WER 28.17 [ 11829 / 41995, 2613 ins, 4076 del, 5140 sub ] [PARTIAL]
# %SER 63.58 [ 4076 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic7.0/callhome_dev//scoring_kaldi/
# 0.7249/0.7250/0.7768/0.8070
# There are several 1best hypothesis failed to get alignment from kaldi

# 8.0
# %WER 44.47 [ 18676 / 41995, 5428 ins, 6956 del, 6292 sub ] [PARTIAL]
# %SER 80.72 [ 5175 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic8.0/callhome_dev//scoring_kaldi/
# 0.6026/0.6026/0.6525/0.7028
# There are several 1best hypothesis failed to get alignment from kaldi

# 9.0
# %WER 65.56 [ 27531 / 41995, 7694 ins, 12782 del, 7055 sub ] [PARTIAL]
# %SER 93.45 [ 5991 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic9.0/callhome_dev//scoring_kaldi/

# 10.0
# %WER 76.74 [ 32225 / 41995, 8349 ins, 16125 del, 7751 sub ] [PARTIAL]
# %SER 96.94 [ 6215 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic10.0/callhome_dev//scoring_kaldi/

# 100.0
# %WER 108.39 [ 45520 / 41995, 3931 ins, 30895 del, 10694 sub ] [PARTIAL]
# %SER 99.75 [ 6395 / 6411 ]
# Scored 6411 sentences, 44 not present in hyp.
# Done: exp/espnet/roshansh_asr_base_sp_conformer_swbd/decode_asr_beam40_nbest100_lm_lm_train_lm_bpe2000_valid.loss.best_asr_model_valid.acc.ave_stochastic100.0/callhome_dev//scoring_kaldi/
