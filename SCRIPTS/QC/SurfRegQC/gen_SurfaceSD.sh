#!/bin/bash
set -x

echo There are $# arguments passed to $0: $*
echo $2

SUBJLIST=$1 #
SUBJPATH=$2 #
LowResMesh=$3
ATLASNAME=$4

SCENE_PATH=$PP_SCRIPTS/QC/SurfRegQC/
for SUBJECT in $SUBJLIST
do
#QUARTER=`grep $SUBJECT subject-quarter.txt | cut -f2`
VERSION=5.3.0-HCP
SEDFILE=gen_scenes.$$.sed

VERSSTRING=fs"$VERSION"
cat > $SEDFILE <<EOF
s#/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls/FCS_040_AMC#$SUBJPATH#g
s#MNI152_T1_1mm_t88#$ATLASNAME#g
s#32k#${LowResMesh}k#g
s#FCS_040_AMC#$SUBJECT#g
#s#diff5.3-mg-5.2#$DIFFSTRING#g
s#fs5.3-mg#$VERSSTRING#g
s#ArealDistortion#MyelinMap_BC#g
EOF


# create scene file
sed -f $SEDFILE $SCENE_PATH"/SurfaceSD_template.scene" > "$SUBJECT"_SurfaceSD.scene


rm $SEDFILE

done


#########################################
exit 0
#########################################

