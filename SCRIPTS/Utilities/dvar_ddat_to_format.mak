#$Header: /data/petsun4/data1/src_solaris/actmapf_4dfp/RCS/format2lst.mak,v 1.2 2009/07/30 05:41:38 avi Exp $
#$Log: format2lst.mak,v $
# Revision 1.2  2009/07/30  05:41:38  avi
# linux compliant
#

PROG	= dvar_ddat_to_format_sol
CSRCS	= dvar_ddat_to_format.c /data/nil-bluearc/raichle/lin64-nilsrc/actmapf_4dfp/expandf.c
OBJS	= ${CSRCS:.c=.o}

.c.o:
	${CC} -c $<

CFLAGS	= -I. -O3
ifeq (${OSTYPE}, linux)
	CC	= gcc ${CFLAGS}
else
	CC	= cc  ${CFLAGS}
endif
LIBS	= -lm

${PROG}: ${OBJS} 
	${CC} -o $@ ${OBJS} -lm

release: ${PROG}
	chmod 771 ${PROG}
#	chgrp program ${PROG}
#	mv ${PROG} ${RELEASE}

clean:
	/bin/rm ${PROG} ${OBJS}
	
