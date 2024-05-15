#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <math.h>
#include <librms.h>

typedef struct {double r, i;} DCMPLX;

static void errm (char *program) {
	fprintf (stderr, "%s error\n", program);
	exit (-1);
}

extern void zgemm_ (char* transa, char* trasnb, int* m, int* n, int* k, DCMPLX* alpha, DCMPLX* A, int* ldA, DCMPLX* B, int* ldB, DCMPLX* beta, DCMPLX *C, int *ldC);
extern void dgemm_ (char* transa, char* trasnb, int* m, int* n, int* k, double* alpha, double* A, int* ldA, double* B, int* ldB, double* beta, double *C, int *ldC);
extern void dgesv_ (int* n, int* nrhs, double* a, int* lda, int* ipiv, double* b, int* ldb, int* info);
extern double dnormal (void);

/***********/
/* globals */
/***********/
static char	program[256];

double **calloc_double2 (int n1, int n2) {
	int	i;
	double	**a;

	if (!(a = (double **) malloc (n1 * sizeof (double *)))) errm (program);
	if (!(a[0] = (double *) calloc (n1 * n2, sizeof (double)))) errm (program);
	for (i = 1; i < n1; i++) a[i] = a[0] + i*n2;
	return a;
}

void free_double2 (double **a) {
	free (a[0]);
	free (a);
}

DCMPLX **calloc_dcmplx2 (int nj, int ni) {
	int	k;
	DCMPLX	**a;

	if (!(a = (DCMPLX **) malloc (nj * sizeof (DCMPLX *)))) errm (program);
	if (!(a[0] = (DCMPLX *) calloc (nj * ni, sizeof (DCMPLX)))) errm (program);
	for (k = 1; k < nj; k++) a[k] = a[0] + k*ni;
	return a;
}

void free_dcmplx2 (DCMPLX **a) {
	free (a[0]);
	free (a);
}

void dcmplx_matlst (DCMPLX **A, int nj, int ni) {
	int	j, i;

	for (i = 0; i < ni; i++) {
		for (j = 0; j < nj; j++) printf ("(%8.4f, %8.4f)", A[j][i].r, A[j][i].i);
		printf ("\n");
	}
}

void dmatlst (double **A, int nj, int ni) {
	int	j, i;

	for (i = 0; i < ni; i++) {
		for (j = 0; j < nj; j++) printf ("%10.4f", A[j][i]);
		printf ("\n");
	}
}

void setprog (char *program, char **argv) {
	char *ptr;

	if (!(ptr = strrchr (argv[0], '/'))) ptr = argv[0]; 
	else ptr++;
	strcpy (program, ptr);
}

int main1 (int argc, char *argv[]) {
	int	i, j, k;
	int	dim = 4;
	DCMPLX	**A, **C;
	DCMPLX 	alpha = {1., 0.}, beta = {0., 0.};

	setprog (program, argv);
	printf ("alpha = (%f, %f)\n", alpha.r, alpha.i);
	printf ("beta  = (%f, %f)\n", beta.r,  beta.i);
	A = calloc_dcmplx2 (dim, dim);
	C = calloc_dcmplx2 (dim, dim);
	for (j = 0; j < dim; j++) for (i = 0; i < dim; i++) {A[j][i].r = dnormal(); A[j][i].i = dnormal();}

	printf ("A\n");
	dcmplx_matlst (A, dim, dim);
	if (1) zgemm_ ("n", "c", &dim, &dim, &dim, &alpha, A[0], &dim, A[0], &dim, &beta, C[0], &dim);
	printf ("A*Ah\n");
	dcmplx_matlst (C, dim, dim);

	free_dcmplx2 (A); free_dcmplx2 (C);
}

int main (int argc, char *argv[]) {
	int	i, j, k, dim = 10, info;
	int	*ipiv;
	double	**T, **A, **B, **C, alpha = 1.0, beta = 0.0;
	
	setprog (program, argv);
	T = calloc_double2 (dim, dim);
	A = calloc_double2 (dim, dim);
	B = calloc_double2 (dim, dim);
	C = calloc_double2 (dim, dim);
	for (j = 0; j < dim; j++) for (i = 0; i < dim; i++) T[j][i] = A[j][i] = dnormal();
	for (j = 0; j < dim; j++) B[j][j] = 1.0;
	if (!(ipiv = (int *) calloc (dim, sizeof (int)))) errm (program);
	printf ("A\n"); dmatlst (A, dim, dim);
	printf ("B\n"); dmatlst (B, dim, dim);
	dgesv_ (&dim, &dim, A[0], &dim, ipiv, B[0], &dim, &info);
	if (info) {
		printf ("dgesv_() error\n");
		exit (-1);
	}
	dgemm_ ("n", "n", &dim, &dim, &dim, &alpha, T[0], &dim, B[0], &dim, &beta, C[0], &dim);
	printf ("X = Ainv in B\n"); dmatlst (B, dim, dim);
	printf ("C = (A in T)*Ainv should be I\n"); dmatlst (C, dim, dim);

	free (ipiv); free_double2 (T); free_double2 (A); free_double2 (B); free_double2 (C);
}

int main0 (int argc, char *argv[]) {
	int	i, j, k, dim = 4, info;
	int 	n = 5, nrhs = 3, lda = 5, ldb = 5;
	int ipiv[5];
	double a[25] = {
		 6.80, -2.11,  5.66,  5.97,  8.23,
		-6.05, -3.30,  5.36, -4.44,  1.08,
		-0.45,  2.58, -2.70,  0.27,  9.04,
		 8.32,  2.71,  4.35, -7.17,  2.14,
		-9.67, -5.14, -7.26,  6.08, -6.87};
	double b[15] = {
		 4.02,  6.19, -8.22, -7.57, -3.03,
		-1.56,  4.00, -8.67,  1.75,  2.86,
		 9.81, -4.09, -4.57, -8.61,  8.99};

	printf("DGESV Example Program Results\n");
	dgesv_ ( &n, &nrhs, a, &lda, ipiv, b, &ldb, &info );
	if (info) {
		printf ("dgesv_() error\n");
		exit (-1);
	}
	for (i = 0; i < 15; i++) printf (" %6.2f", b[i]);
	printf( "\n" );
}
