#!/bin/csh

if($#argv != 6) then
	echo "volume_to_surface <input volume> <surface folder> <output surface root> <vertex space> <sample method> <surface to sample to> <optional: goodvoxels volume>"
	echo "Projects a volume to a surface. Outputs a left and right "
	echo "    hemisphere gifti func surface."
	echo " <input volume> - the volume image you want to project to "
	echo "	the surface. Can be 4dfp or nifiti. Needs extension."
	echo " <surface folder> - folder that contains the surfaces you "
	echo "	wish to project to. Usually in the subjects atlas "
	echo "	folder. If you are using an atlas space input volume, "
	echo "	use the atlas transformed surface folder"
	echo " <output surface root> - the base filename you wish the "
	echo "	output surfaces to be named."
	echo " <vertex space> is 10 for 10k, 32 for 32k and 164 for 164k"
	echo " <Method> - enclosing (effectively nearest neighbor, use for rois) "
	echo "	        ribbon (normal sampling using cylinder, use for evrerything else)"	
	echo "<surface to sample to> - which surface to use: white, midthickness, pial"
	echo "<good voxels> - mask to constrain the surfaces by in volume space."
	exit 1
endif

set Volume = $1	#in surface volume space
set SurfaceFolder = $2	#the atlas transformed surfaces
set OutputSurfaceRoot = $3
set VertexSpace = $4
set Method = $5
set Surface = $6
set GoodVoxels = $7	#optional

switch(`echo $Volume | awk -F . '{print $NF}'`)
	case img:
		$RELEASE/niftigz_4dfp -n $Volume `basename $Volume .4dfp.img`
		set Volume = `basename $Volume .4dfp.img`.nii.gz
		set RemoveTemp = 1
		breaksw
	case gz:
		set RemoveTemp = 0
		breaksw
	case nii:
		set RemoveTemp = 0
		breaksw
endsw
echo $Volume

if($VertexSpace == "164k") then
	set VertexSpace = 164
else if($VertexSpace == "32k") then
	set VertexSpace = 32
else if($VertexSpace == "10k") then
	set VertexSpace = 10
endif

if($Surface == "") then
	set Surface = "midthickness"
endif

if($GoodVoxels == "") then
	set RoiVoxels = ""
else
	set RoiVoxel = "-volume-roi $GoodVoxels"
endif

if($Method == "enclosing") then

	$CARET7DIR/wb_command -volume-to-surface-mapping $Volume ${SurfaceFolder}/*.L.${Surface}.${VertexSpace}k_fs_LR.surf.gii $OutputSurfaceRoot.L.${VertexSpace}k.func.gii -enclosing #-ribbon-constrained ${SurfaceFolder}/*.L.white.${VertexSpace}k_fs_LR.surf.gii ${SurfaceFolder}/*.L.pial.${VertexSpace}k_fs_LR.surf.gii -volume-roi $GoodVoxels -output-weights-text lh_vertex_voxel_weights.txt
	if($status) exit 1

	$CARET7DIR/wb_command -volume-to-surface-mapping $Volume ${SurfaceFolder}/*.R.${Surface}.${VertexSpace}k_fs_LR.surf.gii $OutputSurfaceRoot.R.${VertexSpace}k.func.gii -enclosing #-ribbon-constrained ${SurfaceFolder}/*.R.white.${VertexSpace}k_fs_LR.surf.gii ${SurfaceFolder}/*.R.pial.${VertexSpace}k_fs_LR.surf.gii -volume-roi $GoodVoxels -output-weights-text rh_vertex_voxel_weights.txt
	if($status) exit 1

else if($Method == "ribbon") then

	$CARET7DIR/wb_command -volume-to-surface-mapping $Volume ${SurfaceFolder}/*.L.${Surface}.${VertexSpace}k_fs_LR.surf.gii $OutputSurfaceRoot.L.${VertexSpace}k.func.gii -ribbon-constrained ${SurfaceFolder}/*.L.white.${VertexSpace}k_fs_LR.surf.gii ${SurfaceFolder}/*.L.pial.${VertexSpace}k_fs_LR.surf.gii -output-weights-text lh_vertex_voxel_weights.txt $RoiVoxels 
	if($status) exit 1

	$CARET7DIR/wb_command -volume-to-surface-mapping $Volume ${SurfaceFolder}/*.R.${Surface}.${VertexSpace}k_fs_LR.surf.gii $OutputSurfaceRoot.R.${VertexSpace}k.func.gii -ribbon-constrained ${SurfaceFolder}/*.R.white.${VertexSpace}k_fs_LR.surf.gii ${SurfaceFolder}/*.R.pial.${VertexSpace}k_fs_LR.surf.gii -output-weights-text rh_vertex_voxel_weights.txt $RoiVoxels
	if($status) exit 1
else
	echo "Invalid method entered."
	exit 1
endif


exit 0
