#/bin/csh

pushd /data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_122_A/FCmaps_uwrp

#cat FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout.conc

set format = "4x18+2x21+2x42+5x2+2x12+22x2+3x4+2x14+4x+2x6+2x7+20x+2x21+4x2+2x+3x3+3x2+2x2+15x4+2x10+3x+8x+3x7+8x5+13x16+2x29+2x5+7x38+2x8+11x+6x4+7x24+2x2+10x+5x3+6x3+2x5+2x26+6x7+2x5+2x9+5x9+2x23+4x4+4x2+6x2+4x2+6x+7x2+8x+3x12+4x16+12x7+6x4+9x2(5+6x)+6x4+2x7+3x4+7x+2x3+8x2+2x+14x2+12x9+7x+2x2+12x+5x2+"

#set format = "896+"

    qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout.conc	FCS_122_A_WM_mask		-f$format -l5 -t.15 -n62 -O4 -D -oFCS_122_A_WM_regressors.dat

set E = /data/petsun4/data1/src_solaris/qnt_4dfp/TEST
set D = /data/nil-bluearc/raichle/lin64-nilsrc/qnt_4dfp
#$D/qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout.conc	FCS_122_A_WM_mask		-f$format -l5 -t.15 -n62 -O4 -D -oFCS_122_A_WM_regressors.dat
#$D/qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout_LOCAL.conc	FCS_122_A_WM_mask		-f$format -l5 -t.15 -n62 -O4 -D -oFCS_122_A_WM_regressors.dat # fails
#$D/qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout_LOCAL.conc FCS_122_A_WM_mask		-f$format -l5 -t.15 -n62 -O1    -oFCS_122_A_WM_regressors.dat # fails
#$D/qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout_LOCAL.conc $E/testROIs			-f$format -l5 -t.15 -n62 -O1    -oFCS_122_A_WM_regressors.dat # works
#$D/qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout_LOCAL.conc $REFDIR/glm_atlas_mask_333	-f$format -l5 -t.15 -n62 -O1    -oFCS_122_A_WM_regressors.dat # fails
#$D/qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout_LOCAL.conc $D/testmask30			-f$format -l5 -t.15 -n62 -O1    -oFCS_122_A_WM_regressors.dat # works
#$D/qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout_LOCA1.conc $D/testmask30			-f128+    -l5 -t.15 -n62 -O1    -oFCS_122_A_WM_regressors.dat # works
#$D/qntv_4dfp FCS_122_A_faln_dbnd_xr3d_uwrp_atl_uout_LOCA1.conc $REFDIR/glm_atlas_mask_333	-f128+    -l5 -t.15 -n62 -O1    -oFCS_122_A_WM_regressors.dat # fails

echo "status="$status
