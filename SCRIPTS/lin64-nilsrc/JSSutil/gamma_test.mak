#$Id$
#$Log$

PROG	= gamma_test
CSRCS	= ${PROG}.c JSSstatistics.c
FSRCS	=
JSS	= ${NILSRC}/JSSutil
LIN	= ${NILSRC}/imglin
LOBJS	= ${LIN}/dnormal.o

OBJS	= ${CSRCS:.c=.o} ${FSRCS:.f=.o}

.c.o:
	${CC} -c $<

.f.o:
	${FC} -c $<

CFLAGS	= -O -I${JSS}
ifeq (${OSTYPE}, linux)
	CC	= gcc ${CFLAGS}
else
	CC	= cc  ${CFLAGS}
endif


${PROG}: ${OBJS}
	$(CC) -o $@ ${OBJS} ${LOBJS} -lm

clean:
	rm ${OBJS}

checkout:
	co ${CSRCS} ${FSRCS}

checkin:
	ci ${CSRCS} ${FSRCS}
