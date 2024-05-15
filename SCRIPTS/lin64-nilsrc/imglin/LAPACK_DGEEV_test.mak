PROG	= LAPACK_DGEEV_test
CSRCS	= ${PROG}.c dnormal.c
FSRCS	= 
OBJS 	= ${FSRCS:.f=.o} ${CSRCS:.c=.o}
RMS	= ${NILSRC}/librms
LOBJS	= ${RMS}/matopr.o ${RMS}/eigen.o ${RMS}/param6opr.o

CFLAGS	= -O -I.
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
	chmod 771 ${PROG}
	/bin/mv ${PROG} ${RELEASE}

clean:
	rm ${OBJS} ${PROG}

checkout:
	co $(CSRCS) $(FSRCS) 

checkin:
	ci $(CSRCS) $(FSRCS) 

