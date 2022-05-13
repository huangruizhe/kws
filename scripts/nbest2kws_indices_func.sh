#!/bin/bash
# Copyright (c) 2021, Johns Hopkins University, Ruizhe Huang
# License: Apache 2.0

merge_nbest_by_utt0 () {
    # Merge the nbest list produced by ESPnet to our format

    job_id=$1
    src_dir=$2
    tgt_dir=$3

    n=`ls -d1 $src_dir/logdir/output.${job_id}/*best_recog | wc -l`

    mkdir -p $tgt_dir/temp/${job_id}/
    rm -f $tgt_dir/temp/${job_id}/nbest.txt
    # for each uid in the file
    while read -r line; do
        printf 'merge_nbest_by_utt is processing uid: %s\n' "$line"

        # loop over nbest files
        hypos=""
        for i in $(eval echo "{1..$n}"); do
            f_text=$src_dir/logdir/output.${job_id}/${i}best_recog/text
            f_score=$src_dir/logdir/output.${job_id}/${i}best_recog/score

            (exit 1);   # set the return code $?
            [[ -f $f_text ]] && grep -q $line $f_text;
            if [[ $? -eq 1 ]]; then 
                break
            fi

            hyp=`grep $line $f_text | cut -d' ' -f2-`
            score=`grep $line $f_score | cut -d' ' -f2 | grep -Eo '[+-]?[0-9]+([.][0-9]+)?([eE][+-][0-9]*)?'`

            echo -e "${line}\t${score}\t${hyp}" >>  $tgt_dir/temp/${job_id}/nbest.txt
        done
    done < <(cut -d' ' -f1 $tgt_dir/temp/${job_id}/utt)
    # done < <(echo "en_4938-B_007711-007964")
}

rover_get_sausage () {
    # Produce sausage from nbest with ROVER

    job_id=$1
    src_dir=$2
    tgt_dir=$3

    # n=`ls -d1 $src_dir/logdir/output.${job_id}/*best_recog | wc -l`

    rm -f $tgt_dir/temp/${job_id}/sausage.ctm
    # for each uid in the file
    while read -r line; do
        printf 'rover_get_sausage is processing uid: %s\n' "$line"

        readarray -t my_nbest < <(grep $line $tgt_dir/temp/${job_id}/nbest.txt | cut -d' ' -f1,3- )

        hypos=""
        arraylength=${#my_nbest[@]}  # get length of an array
        # use for loop to read all values and indexes
        for (( i=0; i<${arraylength}; i++ )); do
            # echo "index: $i, value: ${array[$i]}"
            my_ctm=`echo ${my_nbest[$i]} | awk '{
                if (NF > 1)
                    for (i = 2; i <= NF; i++) print $1 " A 0 0 " $i;
                else
                    print $1 " A 0 0 <eps>";
            }'`
            my_nbest[$i]="$my_ctm"   # we save it to a bash array variable, hoping to keep data in RAM, avoiding disk I/O
            hypos="$hypos -h <(echo \"\${my_nbest[$i]}\") ctm "
        done

        if [[ $arraylength -eq 1 ]]; then
            echo "This uid has only one hypothesis."
            hypos="$hypos -h <(echo \"\${my_nbest[0]}\") ctm "   # copy the same hypo -- the sausauge will always be linear, 
                                                                 # but ROVER will not complain any more.
                                                                 # Otherwise: rover: Req'd Hyp File names, 2 or more
        fi

        # Note1: eval: https://stackoverflow.com/a/794783/4563935
        # Note2: we use -s option here to avoid ROVER tranforming uid to all lower-cases
        # Note3: without "cat -", the output file will be re-written for every uid, not sure why.
        eval rover -m oracle -f 0 -s $hypos -o /dev/stdout | cat - >> $tgt_dir/temp/${job_id}/sausage.ctm
    done < <(cut -d' ' -f1 $tgt_dir/temp/${job_id}/utt)
    # done < <(echo "en_4938-B_007711-007964")
}

get_w_scores () {
    # Obtain word-level confidence scores from the token-level scores for the nbest list

    job_id=$1
    length_bonus=$2
    nbest_dir=$3
    score_type=$4

    nbest=`ls -d1 $nbest_dir/logdir/output.${job_id}/*best_recog | wc -l`
    for ibest in `seq 1 $nbest`; do 
        echo "$(date) ibest=$ibest"
        script=/export/fs04/a12/rhuang/kws/kws/local/token_scores_2_word_scores.py
        python $script --score $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/score \
            --score_details $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/score_details \
            --token $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/token \
            --text $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/text \
            --wdscore $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/word_score_${score_type} \
            --length_bonus $length_bonus \
            --score_type $score_type \
            --weights "0.7 0.3 0.1 0.3"
    done

    echo "Output:" $nbest_dir/logdir/output.${job_id}/${ibest}best_recog/word_score_${score_type}
}

# execute the command as it is
$@
