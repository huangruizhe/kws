cd /home/hltcoe/rhuang/espnet/egs2/swbd/asr1
f=dump/fbank_pitch/callhome_dev/feats.scp
cp $f $f.backup
sed -i 's/\/export\/fs04\/a12\/rhuang\/espnet\/egs2\/swbd\/asr1\//\/home\/hltcoe\/rhuang\/espnet\/egs2\/swbd\/asr1\//g' $f