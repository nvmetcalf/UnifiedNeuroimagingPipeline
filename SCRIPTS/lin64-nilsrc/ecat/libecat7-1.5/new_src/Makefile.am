# automake file for libecat, process with automake
# Andy Loening 2001.09.30           

# INCLUDES = -I/usr/include/sys

lib_LTLIBRARIES = libecat.la

libecat_la_LDFLAGS = -version-info $(LIBVERSION)

include_HEADERS = \
        matrix.h

libecat_la_SOURCES = \
	analyze.c \
	analyze.h \
	convert_64.c \
	convert_70.c \
	crash.c \
	interfile.c \
	interfile.h \
	isotope_info.h \
	load_volume7.c \
	load_volume7.h \
	machine_indep.c \
	machine_indep.h \
	matrix.c \
	matrix_64.c \
	matrix_64.h \
	matrix_extra.c \
	matrix_slice.c \
	matrix_xdr.c \
	matrix_xdr.h \
	num_sort.c \
	num_sort.h \
	rts_cmd.c \
	rfa_xdr.c \
	rfa_xdr.h \
	save_volume7.c \
	sino_dets.c 

# Following removed in 2004.07.20 release of orig_source
#	$(COMPRESS_SRCS)
#
#COMPRESS_SRCS = \
#	z_matrix.c \
#	compress.c \
#	compress.h \
#	c_uvlc.c \
#	d_uvlc.c \
#	uvlc.c \
#	uvlc.h 
