# automake file for libecat utils, process with automake
# Andy Loening 2001.09.30

LDADD = -lecat -lm
INCLUDES = -I../src 
AM_LDFLAGS = -L../src

bin_PROGRAMS = \
	matlist \
	show_header \
	applynorm \
	get_axial_lor \
	matcopy \
	cti2analyze \
	analyze2ifh \
	matinfo \
	read_ecat \
	write_ecat \
	scan2if \
	byte_volume \
	imagemath \
	wb_assemble \
	make_volume


applynorm_SOURCES = \
	applynorm.c \
	ecat_model.c \
	ecat_model.h 

get_axial_lor_SOURCES = \
	get_axial_lor.c \
	ecat_model.c \
	ecat_model.h \
	plandefs.h \
	plandefs.c

wb_assemble_SOURCES = \
	wb_assemble.c \
	ecat_model.c \
	ecat_model.h 
