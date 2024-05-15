#!/bin/bash
set -x

echo There are $# arguments passed to $0: $*
echo $2
OUTDIR=$3
SUBJLIST=$2
SUBJPATH=$1

SCENE_PATH=$PP_SCRIPTS/QC/VolumeRegQC
for SUBJECT in $SUBJLIST
do
VERSION=5.3.0-HCP

SEDFILE=$OUTDIR/gen_scenes.$$.sed


#if [ "$SUBJECT" = "" ]
#then
#  echo "usage:  gen_scenes_two-structurals_"$QUARTER".sh case-number"
#  exit
#fi
#if [ "$QUARTER" = "" ]
#then
#  echo "exiting - not in subject-quarter.txt; path can't be determined."
#  exit
#fi
#if [ "$QUARTER" = "Q1" ]
#then
#  echo "exiting - Q1 path hassles"
#  exit
#fi

#DIFFSTRING=diff_fs"$VERSION"-fs5.2
#DISTSTRING=Distance_fs5.2-fs"$VERSION"
VERSSTRING=fs"$VERSION"
cat > $SEDFILE <<EOF
s#/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls#$SUBJPATH#g
s#../../../../Projects/FCStroke_2016/Controls#$SUBJPATH#g
s#FCS_040_AMC#$SUBJECT#g
s#atlas#Anatomical/Volume/T1#g
#s#diff5.3-mg-5.2#$DIFFSTRING#g
s#fs5.3-mg#$VERSSTRING#g
s#ArealDistortion#MyelinMap_BC#g
s#_T1T#_T1#g
EOF

#cd $OUTDIR

# create scene file
#echo "s#$SRCDIROLD/#$SRCDIRNEW/#g" >> $SEDFILE
sed -f $SEDFILE $SCENE_PATH"/StructuralETA_template.scene" > $OUTDIR/"$SUBJECT"_StructuralETA.scene

rm $SEDFILE

done


#########################################
exit 0
#########################################

