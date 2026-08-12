#!/bin/bash
#OFFSCREEN RENDERING OF SCENE TO AN IMAGE FILE
set -x

SUBJLIST=$1
IMG_WIDTH=$2
IMG_HEIGHT=$3

for SUBJECT in $SUBJLIST
do
SCENE_FILE="$SUBJECT"_SurfaceSD.scene
# Freesurfer 5.3.0-HCP vs 5.2: distance between midthickness

PNG="$SUBJECT"_SurfaceSD.png
wb_command -show-scene $SCENE_FILE 1 $PNG $IMG_WIDTH $IMG_HEIGHT

#PNG=$OUTDIR/QC/"$SUBJECT"_covall.png
#wb_command -show-scene $SCENE_FILE 3 $PNG $IMG_WIDTH $IMG_HEIGHT
done
###############################
exit
###############################
wb_command -show-scene
      <scene-file>
      <scene-name-or-number>
      <image-file-name>
      <image-width>
      <image-height>

      Render content of browser windows displayed in a scene into image
      file(s).  The image file name should be similar to "capture.png".  If
      there is only one image to render, the image name will not change.  If
      there is more than one image to render, an index will be inserted into
      the image name: "capture_01.png", "capture_02.png" etc.

      The image format is determined by the image file extension.
      Image formats available on this sytem are:
      bmp
      png
      ppm
      xbm
      xpm
      Note: Available image formats may vary by operating system.

      Descriptions of parameters and options:

      <scene-file> - scene file
      <scene-name-or-number> - name or number (starting at one) of the scene in
         the scene file
      <image-file-name> - output image file name
      <image-width> - width of output image(s)
      <image-height> - height of output image(s)

