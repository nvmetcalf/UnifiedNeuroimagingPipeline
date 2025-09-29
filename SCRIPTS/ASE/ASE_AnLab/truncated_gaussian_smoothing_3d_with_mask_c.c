#include <stdio.h>
#include <stdlib.h>
#include <mex.h>
#include <math.h>
#include <time.h>

#define X3(i, j, k)  (k)*dim12 + (j)*dim1+(i)

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
   double *pointer_in, *pointer_out, *pointer_mk;
   double ***im1, ***im2, ***mk;
   const *dims;
   int dim1, dim2, dim3, dim12, dim1max, dim2max, i, j, k, ii, jj, kk, index;
   int half_widthx, half_widthy, half_widthz, widthx, widthy, widthz;
   int si, ei, sj, ej, sk, ek;
   int si_window, ei_window, sj_window, ej_window, sk_window, ek_window;

   double fwhmx, fwhmy, fwhmz, sigmax, sigmay, sigmaz, gx, gy, gz;
   double dx, dy, dz, cx, cy, cz, tempf, tempf_total, tempw, temp_im;
   double gaussian3d[100][100][100];
   double pi = 3.1415926;

   dims = mxGetDimensions(prhs[0]);
   int ndim = (int)mxGetNumberOfDimensions(prhs[0]);
   dim1 = (int) dims[0];
   dim2 = (int) dims[1];
   dim3 = (int) dims[2];
   dim1max = dim1-1;
   dim2max = dim2-1;

   dim12 = dim1*dim2;
   fwhmx = mxGetPr(prhs[2])[0];
   fwhmy = mxGetPr(prhs[3])[0];
   fwhmz = mxGetPr(prhs[4])[0];

   half_widthx = mxGetPr(prhs[5])[0];
   half_widthy = mxGetPr(prhs[6])[0];
   half_widthz = mxGetPr(prhs[7])[0];

   plhs[0] = mxCreateNumericArray(ndim, dims, mxDOUBLE_CLASS, mxREAL);
   pointer_in = mxGetPr(prhs[0]);
   pointer_mk = mxGetPr(prhs[1]);
   pointer_out = mxGetPr(plhs[0]);

   sigmax = fwhmx / (2*sqrt(2*log(2)));
   sigmay = fwhmy / (2*sqrt(2*log(2)));
   sigmaz = fwhmz / (2*sqrt(2*log(2)));

   widthx = half_widthx*2+1;
   widthy = half_widthy*2+1;
   widthz = half_widthz*2+1;

   cx = (0+widthx-1)/2;
   cy = (0+widthy-1)/2;
   cz = (0+widthz-1)/2;

   tempf = 0;
   for(i=0; i<widthx; i++)
      for(j=0; j<widthy; j++)
         for(k=0; k<widthz; k++)
         {
	    dx = i - cx;
	    dy = j - cy;
	    dz = k - cz;

	    gx = exp(-dx*dx/(2*sigmax*sigmax))/(sqrt(2*pi)*sigmax);
	    gy = exp(-dy*dy/(2*sigmay*sigmay))/(sqrt(2*pi)*sigmay);
	    gz = exp(-dz*dz/(2*sigmaz*sigmaz))/(sqrt(2*pi)*sigmaz);

	    gaussian3d[i][j][k] = gx*gy*gz;
	    tempf += gaussian3d[i][j][k];
	}

   for(i=0; i<widthx; i++)
      for(j=0; j<widthy; j++)
         for(k=0; k<widthz; k++)
            gaussian3d[i][j][k] /= tempf;

   printf("dims %d %d %d, fwhm %f %f %f, sigma %f %f %f  Width %d %d %d\n", dim1, dim2, dim3, fwhmx, fwhmy, fwhmz, sigmax, sigmay, sigmaz, widthx, widthy, widthz);
   

   /**************************************************************************/
   im1 = (double***)malloc(sizeof(double**)*dim1);
   for(i=0; i<dim1; i++)
      im1[i] = (double**)malloc(sizeof(double*)*dim2);

   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         im1[i][j] = (double*)malloc(sizeof(double)*dim3);

   im2 = (double***)malloc(sizeof(double**)*dim1);
   for(i=0; i<dim1; i++)
      im2[i] = (double**)malloc(sizeof(double*)*dim2);

   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         im2[i][j] = (double*)malloc(sizeof(double)*dim3);

   mk = (double***)malloc(sizeof(double**)*dim1);
   for(i=0; i<dim1; i++)
      mk[i] = (double**)malloc(sizeof(double*)*dim2);

   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         mk[i][j] = (double*)malloc(sizeof(double)*dim3);

   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         for(k=0; k<dim3; k++)
            im2[i][j][k] = 0;

   /*printf("done with memory allocation !\n");*/

   /* /////////////////////////////////////////////////////////////////////// */
   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         for(k=0; k<dim3; k++)
         {
            im1[i][j][k] = pointer_in[X3(i,j,k)];
            mk[i][j][k] = pointer_mk[X3(i,j,k)];
         }

   /*printf("1\n");*/

   for(k=0; k<dim3; k++)
      for(i=0; i<dim1; i++)
         for(j=0; j<dim2; j++)
         {
            if(mk[i][j][k]<0.5)
               continue;

            si = i-half_widthx; ei = i+half_widthx;
            sj = j-half_widthy; ej = j+half_widthy;
            sk = k-half_widthz; ek = k+half_widthz;

            si_window = 0;  ei_window = widthx-1;
            sj_window = 0;  ej_window = widthy-1;
            sk_window = 0;  ek_window = widthz-1;

            /*%%%%%%%%%%%%%%%%%%%%adjust window position*/
            if(sk<0)
            {
               sk_window = sk_window-sk;;
               sk = 0;
	    }

            if(ek>dim3-1)
            {
               ek_window = ek_window - (ek-(dim3-1));
               ek = dim3-1;
	    }

            if(si<0)
            {
               si_window = si_window-si;
               si = 0;
	    }

            if(ei>dim1-1)
            {
               ei_window = ei_window - (ei-(dim1-1));
               ei = dim1-1;
	    }

            if(sj<0)
            {
               sj_window = sj_window-sj;
               sj = 0;
	    }

            if(ej>dim2-1)
            {
               ej_window = ej_window - (ej-(dim2-1));
               ej = dim2-1;
	    }

	    /**********************************************************************************/
            index = 0;
            tempf = 0;
            tempf_total = 0;

            for(kk=sk; kk<=ek; kk++)
               for(ii=si; ii<=ei; ii++)
                  for(jj=sj; jj<=ej; jj++)
                  {
		     if(mk[ii][jj][kk] < 0.5)
			continue;

		     temp_im = im1[ii][jj][kk];
		     tempw = gaussian3d[si_window+ii-si][sj_window+jj-sj][sk_window+kk-sk];
		     tempf_total += temp_im * tempw;
		     tempf += tempw;
		  }

		 im2[i][j][k] = tempf_total / tempf;
         }

   /* /////////////////////////////////////////////////////////////////////// */
   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         for(k=0; k<dim3; k++)
             pointer_out[X3(i,j,k)] = im2[i][j][k];


   /* /////////////////////////////////////////////////////////////////////// */
   /* free some memories */

   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         free(im1[i][j]);

   for(i=0; i<dim1; i++)
      free(im1[i]);

   free(im1);

   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         free(im2[i][j]);

   for(i=0; i<dim1; i++)
      free(im2[i]);

   free(im2);

   for(i=0; i<dim1; i++)
      for(j=0; j<dim2; j++)
         free(mk[i][j]);

   for(i=0; i<dim1; i++)
      free(mk[i]);

   free(mk);

   return;
}


