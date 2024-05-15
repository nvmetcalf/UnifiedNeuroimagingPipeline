PROG	= BLAS_TEST
CSRCS	= ${PROG}.c dnormal.c
FSRCS	= 
OBJS 	= ${FSRCS:.f=.o} ${CSRCS:.c=.o}
RMS	= ${NILSRC}/librms
LOBJS	= ${RMS}/dmatopr.o

CFLAGS	= -O -I${RMS} -I.
ifeq (${OSTYPE}, linux)
	CC	= gcc ${CFLAGS}
	FC	= gcc -O -ffixed-line-length-132 -fno-second-underscore
	LIBS	= -lm -lgfortran -llapack -lblas
else
	CC	= cc ${CFLAGS}
	FC	= f77 -O -I4 -e
	LIBS	= -lm
endif

${PROG}: ${OBJS}
	${FC} -o $@ ${OBJS} ${LOBJS} ${LIBS}

.c.o:
	$(CC) -c $<

.f.o:
	$(FC) -c $<

release: ${PROG}
	chmod 775 ${PROG}
	/bin/mv ${PROG} ${RELEASE}

clean:
	rm ${OBJS} ${PROG}

checkout:
	co $(CSRCS) $(FSRCS) 

checkin:
	ci $(CSRCS) $(FSRCS) 

