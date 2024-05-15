#!/bin/sh

# this script sets up the source directory from the 
# original source,  patches, and new makefiles

#make the source directory for libecat
cp \
    orig_src/README \
    orig_src/analyze.c \
    orig_src/analyze.h \
    orig_src/convert_64.c \
    orig_src/convert_70.c \
    orig_src/copyright \
    orig_src/crash.c \
    orig_src/interfile.c \
    orig_src/interfile.h \
    orig_src/isotope_info.h \
    orig_src/load_volume7.c \
    orig_src/machine_indep.c \
    orig_src/machine_indep.h \
    orig_src/matrix.c \
    orig_src/matrix.h \
    orig_src/matrix_64.c \
    orig_src/matrix_64.h \
    orig_src/matrix_extra.c \
    orig_src/matrix_slice.c \
    orig_src/matrix_xdr.c \
    orig_src/matrix_xdr.h \
    orig_src/num_sort.c \
    orig_src/num_sort.h \
    orig_src/rfa_xdr.c \
    orig_src/rfa_xdr.h \
    orig_src/rts_cmd.c \
    orig_src/save_volume7.c \
    orig_src/sino_dets.c \
    new_src/Makefile \
    src

# the following were removed from the 2004.07.20 source code
# released by Sibomona.  Maybe for licensing reasons?
#    orig_src/lib_compress/c_uvlc.c \
#    orig_src/lib_compress/compress.c \
#    orig_src/lib_compress/compress.h \
#    orig_src/lib_compress/d_uvlc.c \
#    orig_src/lib_compress/uvlc.c \
#    orig_src/lib_compress/uvlc.h \
#    orig_src/lib_compress/z_matrix.c \

pushd src
ln -sf ../new_src/Makefile.* ./
ln -sf ../new_src/.deps ./
popd

# apply my patches
patch -d src -p1 < new_src/src_2006.03.29_AML1.patch


#make the source directory for the utils
cp \
    orig_src/utils/analyze2ifh.c \
    orig_src/utils/applynorm.c \
    orig_src/utils/byte_volume.c \
    orig_src/utils/count.c \
    orig_src/utils/cti2analyze.c \
    orig_src/ecat_model.c \
    orig_src/ecat_model.h \
    orig_src/utils/get_axial_lor.c \
    orig_src/utils/imagemath.c  \
    orig_src/utils/make_volume.c \
    orig_src/utils/matcopy.c \
    orig_src/utils/matinfo.c \
    orig_src/utils/matlist.c \
    orig_src/utils/phantom_attn.c \
    orig_src/plandefs.c \
    orig_src/plandefs.h \
    orig_src/load_volume.h \
    orig_src/utils/read_ecat.c \
    orig_src/utils/scan2if.c \
    orig_src/utils/scanmath.c \
    orig_src/utils/scanmu.c \
    orig_src/utils/scanmult.c \
    orig_src/utils/scanshift.c \
    orig_src/utils/show_header.c \
    orig_src/utils/updateanh.c \
    orig_src/utils/wb_assemble.c \
    orig_src/utils/wb_build.c \
    orig_src/utils/wb_scan_assemble.c \
    orig_src/utils/write_ecat.c \
    new_utils/Makefile \
    utils


pushd utils
ln -sf ../new_utils/Makefile.* ./
ln -sf ../new_utils/.deps ./
popd

patch -d utils -p1 < new_utils/utils_2006.03.29_AML1.patch
