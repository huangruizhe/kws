#!/bin/bash

cd /export/fs04/a12/rhuang/espnet/egs2/swbd/asr12

####################################
# build index
####################################
cat simple_lattice1/clat.txt | utils/sym2int.pl --map-oov "<unk>" -f 3 simple_lattice1/words.txt | \
  lattice-determinize ark:- ark:-  | \
  lattice-to-kws-index --max-states-scale=100000 --allow-partial=true \
    --frame-subsampling-factor=3 --max-silence-frames=50 --strict=true ark:simple_lattice1/utt.map ark,t:- ark:- | \
  kws-index-union --skip-optimization=true --strict=true --max-states=10000 ark:- "ark,t:simple_lattice1/index.1.txt"

mkdir -p simple_lattice1/kws_indices_2
gzip < simple_lattice1/index.1.txt > simple_lattice1/kws_indices_2/index.1.gz

####################################
# convert keywords to wfst
####################################
cat simple_lattice1/keywords.txt | \
    /export/fs04/a12/rhuang/kws/kws_exp/shay/s5c/local/kws/keywords_to_indices.pl \
    --map-oov 7 simple_lattice1/words.txt | \
    sort -u > simple_lattice1/keywords.int

transcripts-to-fsts ark:simple_lattice1/keywords.int \
      ark,scp,t:simple_lattice1/keywords.fsts,- | sort -o simple_lattice1/keywords.scp

vi simple_lattice1/keywords.fsts

####################################
# search
####################################
mkdir -p simple_lattice1/kws_output

kws-search --strict=false --negative-tolerance=-1 \
    --frame-subsampling-factor=3 \
    "ark:gzip -cdf simple_lattice1/kws_indices_2/index.1.gz|" "ark:simple_lattice1/keywords.fsts" \
    "ark,t:| sort -u | gzip -c > simple_lattice1/kws_output/result.1.gz" \
    "ark,t:| sort -u | gzip -c > simple_lattice1/kws_output/stats.1.gz" 

ls simple_lattice1/kws_output
