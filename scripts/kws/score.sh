#!/usr/bin/env bash

# Copyright 2012-2018  Johns Hopkins University (Author: Guoguo Chen, Yenda Trmal)
# Apache 2.0.

# Begin configuration section.
lats_dir=
kws_data_dir=
indices_tag=""
cmd=run.pl
stage=0
ntrue_from=    # It should be an $kws_outputdir
max_distance=50
sweep_step=0.005
# End configuration section.


# echo $0 $@
[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

set -e -o pipefail

indices_dir=$lats_dir/kws_indices${indices_tag}
kwsoutputdir=$indices_dir/kws_results
echo "The KWS results is taken from: $kwsoutputdir"

trials=$(cat $kws_data_dir/trials)
mkdir -p $kwsoutputdir/log/

if [ $stage -le 0 ] ; then
  if [ -z "$ntrue_from" ]; then
    mkdir -p ${kwsoutputdir}/details/
    mkdir -p ${kwsoutputdir}/scoring/

    # as we need to sweep through different ntrue-scales we will
    # we will do it in one parallel command -- it will be more effective
    # than sweeping in a loop and for all lmwts in parallel (as usuallyu
    # there will be just a couple of different lmwts, but the ntrue-scale
    # has a larger dynamic range

    #$cmd NTRUE=1:21 $kwsoutputdir/log/score.${LMWT}.NTRUE.log \
    #  ntrue=\$\(perl -e 'print 1+(NTRUE-1)/5.0' \) '&&' \
    #$cmd NTRUE=1:50 $kwsoutputdir/log/score.${LMWT}.NTRUE.log \
    #  ntrue=\$\(perl -e 'print NTRUE/10.0' \) '&&' \
    $cmd NTRUE=1:21 $kwsoutputdir/log/score.${LMWT}.NTRUE.log \
      ntrue=\$\(perl -e 'print 1+(NTRUE-1)/5.0' \) '&&' \
      cat ${kwsoutputdir}/results \|\
        local/kws/normalize_results_kst.pl --trials $trials --ntrue-scale \$ntrue \|\
        local/kws/filter_kws_results.pl --probs --nbest 200   \|\
        compute-atwv --max_distance=${max_distance} $trials ark,t:$kws_data_dir/hitlist ark:- \
        \> ${kwsoutputdir}/scoring/score.NTRUE.txt   # no need to set sweep-step here

    ntrue=$(grep ATWV ${kwsoutputdir}/scoring/score.*.txt | \
            sort -k2,2nr -t '='  | head -n 1 | \
            sed 's/.*score\.\([0-9][0-9]*\)\.txt.*/\1/g')
    #The calculation of ntrue must be the same as in the command above
    echo "$ntrue" > ${kwsoutputdir}/details/ntrue_raw
    ntrue=$(perl -e "print 1+($ntrue-1)/5.0")
    echo "$ntrue" > ${kwsoutputdir}/details/ntrue

  else
    mkdir -p ${kwsoutputdir}/details/
    mkdir -p ${kwsoutputdir}/scoring/

    cp ${ntrue_from}/details/ntrue  ${kwsoutputdir}/details/ntrue
    [ -f  ${ntrue_from}/details/ntrue_raw ] && \
      cp ${ntrue_from}/details/ntrue_raw  ${kwsoutputdir}/details/ntrue_raw
    echo "$ntrue_from" > ${kwsoutputdir}/details/ntrue_from
  fi
fi

if [ $stage -le 1 ] ; then
  cat ${kwsoutputdir}/results |\
    local/kws/normalize_results_kst.pl --trials $trials --ntrue-scale $(cat ${kwsoutputdir}/details/ntrue) |\
    local/kws/filter_kws_results.pl --probs --nbest 200000 \
    > ${kwsoutputdir}/details/results
    
  cat ${kwsoutputdir}/details/results |\
      compute-atwv --max_distance=${max_distance} --sweep-step=${sweep_step} $trials ark,t:$kws_data_dir/hitlist ark:- \
      ${kwsoutputdir}/details/alignment.csv > ${kwsoutputdir}/details/score.txt 2>$kwsoutputdir/log/score.final.LMWT.log
  cp ${kwsoutputdir}/details/score.txt ${kwsoutputdir}/score.txt
  
  if [ -f $kws_data_dir/categories ]; then
    cat ${kwsoutputdir}/details/alignment.csv |\
      perl local/search/per_category_stats.pl --sweep-step ${sweep_step}  $trials \
      $kws_data_dir/categories > ${kwsoutputdir}/details/per-category-score.txt      
  else
    echo "$0: Categories file not found, not generating per-category scores"
  fi
fi

[[ -d ${kwsoutputdir}/details_${max_distance} ]] && rm -r ${kwsoutputdir}/details_${max_distance}
[[ -d ${kwsoutputdir}/scoring_${max_distance} ]] && rm -r ${kwsoutputdir}/scoring_${max_distance}
mv ${kwsoutputdir}/details ${kwsoutputdir}/details_${max_distance}
mv ${kwsoutputdir}/scoring ${kwsoutputdir}/scoring_${max_distance}

echo max_distance=$max_distance ntrue_raw=$(cat ${kwsoutputdir}/details_${max_distance}/ntrue_raw)
readarray -t results < <(cat ${kwsoutputdir}/details_${max_distance}/score.txt | rev | cut -d' ' -f1 | rev); 
echo ${results[0]}/${results[2]}/${results[4]}/${results[1]}

echo "$0: Done: ${kwsoutputdir}/details_${max_distance}"
exit 0;


