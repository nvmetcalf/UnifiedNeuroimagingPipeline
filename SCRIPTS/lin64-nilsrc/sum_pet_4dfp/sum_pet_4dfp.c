/*$Header: /data/petsun4/data1/src_solaris/sum_pet_4dfp/RCS/sum_pet_4dfp.c,v 1.3 2013/06/25 13:52:04 jon Exp $*/

/*$Log: sum_pet_4dfp.c,v $
 *Revision 1.3  2013/06/25 13:52:04  jon
 *changed fopen to rb
 *
 * Revision 1.2  2011/09/15  14:30:19  jon
 * More documentation added. Improved usage statement.
 * Will now calculate startTime from midpoint and frame duration.
 *
 *
 * Revision 1.1  2011/01/04  15:58:01  jon
 * Initial revision
 *
 *
 */

#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <ctype.h>
#include <string.h>
#include <unistd.h>
#include <endianio.h>
#include <Getifh.h>
#include <rec.h>

#define MAXL	256

void setprog (char *program, char **argv) {
	char *ptr;

	if (!(ptr = strrchr (argv[0], '/'))) ptr = argv[0]; 
	else ptr++;
	strcpy (program, ptr);
}

static char rcsid[] = "$Id: sum_pet_4dfp.c,v 1.4 2023/06/14 11:04:04 metcalfn Exp $";
int main (int argc, char *argv[]) {
/*************/
/* image I/O */
/*************/
	FILE		*fp_img, *fp_out;
	FILE		*recfp;
	char		*str, frame[MAXL], string[MAXL], recstring[MAXL];
    
	float		time, start, frameMin, frameMax, decayCor, decayCor_first;
	char		imgfile[MAXL], recfile[MAXL];
	char		outfile[MAXL];
	char		imgroot[MAXL];
	char		outroot[MAXL];
	float		scaleFactor = 1.0;
	int		istart = 1;
	int		iend   = 1;
	char *timings;
/**************/
/* processing */
/**************/
	IFH		ifh;
	int		imgdim[4], dimension, orient, isbig;
	float		durationTotal, duration;
	float		voxdim[3];	
	float		*image3d, *img;
	char		control = '\0';
	char		delims[] = "\t";
	float		startTime = 0.0;
	float		halflife = 0.0;
	float		left, right, numerator, dc;
	
/***********/
/* utility */
/***********/
	int			p, c, i, k, j, frameCounter;
	char 		*ptr, command[4*MAXL], program[MAXL];

/*********/
/* flags */
/*********/
	int		test = 0;
	int		status = 0;
	int		exists_oldrec;
	int		USEFIRST = 0;
	
	printf ("%s\n", rcsid);
	setprog (program, argv);

/************************/
/* process command line */
/************************/

	for (k = 0, i = 1; i < argc; i++) {
		if (*argv[i] == '-' && i > 2) {
			strcpy (command, argv[i]); ptr = command;
			
			while (c = *ptr++) switch (c) {
				case '@': control = *ptr++;		*ptr = '\0'; break;
				case 'h': halflife = atof (ptr);	*ptr = '\0'; break;
				case 's': scaleFactor = atof (ptr);	*ptr = '\0'; break;
				case 'd': USEFIRST++;	break;
			}
			strcpy (command, argv[i]); ptr = command;
			   
			while (c = *ptr++) switch (c) {
			}
		} else switch (k) {
                        case 0: getroot (argv[i], imgroot);		k++; break;
				    case 1: timings = argv[i];		k++; break;
                        case 2: istart = atoi (argv[i]);		k++; break;
                        case 3: iend = atoi (argv[i]);			k++; break;
                        case 4: getroot (argv[i], outroot);		k++; break;
		}
	} 
	if (k < 2) {
			printf ("Usage:\tsum_pet_4dfp <input_4dfp> <input timings> <first frame> <last frame> <-hhalf-life> [output_4dfp]\n");
			printf ("\toptions:\n");
			printf ("\t-h<flt>\thalf-life in seconds\n");
			printf ("\t-s<flt>\tfinal additional scaleing\n");
			printf ("\t-d\tuse the decay correction of the first frame in the series\n");
			printf ("\t-@<b|l>\toutput big or little endian (default input endian)\n");
		
			printf ("e.g.,\tsum_pet_4dfp p8932 p8932_timings.txt 2 6 -h122.24 p8932_2-6\n");

			printf ("     \tDefault output appends _vsum to filename. \n");

			printf ("     \tRequires timings to be in the following formatted tab delimited columns:\n");
			printf ("     \tDecayFactor FrameTimesStart FrameDuration FrameReferenceTime\n");
			printf ("     \n\tEach row is a frame in order of acquisition without a header.\n");

			exit (1);
	}

/**************************************************/
/* parse out output filename extension if present */
/* or create output filename if not given         */
/**************************************************/

	sprintf (imgfile, "%s.4dfp.img", imgroot);
	
        if (!strlen (outroot)) 
        	sprintf (outroot, "%s_vsum", imgroot); 
	sprintf (outfile, "%s.4dfp.img", outroot);
	
	if (get_4dfp_dimoe (imgfile, imgdim, voxdim, &orient, &isbig) < 0) errr (program, imgfile);
	if (Getifh (imgfile, &ifh)) errr (program, imgroot);
	if (!control) control = (isbig) ? 'b' : 'l';
	dimension = imgdim[0] * imgdim[1] * imgdim[2];
	
	/*if(imgdim[3] == 1){
	  printf("imgdim[3]  = %d\n",imgdim[3]);
	  errr (program, imgfile);
	}*/
	
	printf("istart = %d iend = %d\n",istart, iend);
	if(istart < 1 || iend > imgdim[3]){
	   
	   errr (program, imgfile);
	}

/****************/
/* alloc buffer */
/****************/

	if (!(img =     (float *) calloc (dimension,  sizeof (float))))	errm (program);
	if (!(image3d = (float *) malloc (dimension * sizeof (float)))) errm (program);

/***********/
/* process */
/***********/
    if (!(recfp = fopen (timings, "r"))) errr (program, timings);
	if (!(fp_img = fopen (imgfile, "rb"))) errr (program, imgfile);
	if (!(fp_out = fopen (outfile, "wb"))) errw (program, outfile);

	fprintf (stdout, "Reading: %s\n", imgfile);
	frameCounter = 1;
	durationTotal = 0;

	for (k = 0; k <= imgdim[3]-1; k++) { /* Each Frame */
		
		fseek (fp_img, (long) k * dimension * sizeof (float), SEEK_SET);
		if (eread (image3d, dimension, isbig, fp_img)) errr (program, imgfile);

		if (k >= istart-1 &&  k <= iend-1)
		{			/* frame in range to be summed */
			printf("Frame: %i\n", k);
			duration = decayCor = 0;                          	/* initialize for each frame */
			
			int j = 0;
			while (fgets (recstring, MAXL, recfp)) 
			{
			/* rec file one line at a time */
				if (k == j) 
				{			/* if "frame" line is in recstring */
                        	printf ("Input= %s", recstring);			/* print Frame_# line */
					str = strstr(recstring," ");			/* remove leading spaces */
					//str = strpbrk(str,"-.0123456789");	/* point to first digit  */
					
					/*strcpy (string, str);	*/		/* Test: copy to preserve str */
					/*printf ("str2=%s", str);*/		/* Test: debuging output */
					
					i=1;					/* column counter */
					str = strtok( recstring, delims );		/* divide str into tokens using delims */

					while( str != NULL ) {
						
						if(i==3)duration = atof(str);	/* length of each frame */
						if(i==4){			
						   time = atof(str);		/* midpoint or DICOM ref_time */
										/* calculate startTime using midpoint */
						   if(k==istart-1)startTime = time - ( duration / 2 );
						}
						if(i==2){
						   start = atof(str);		/* frame start time in msec */
						   start = start;	/* convert to sec */
						   /* if(k==istart-1)startTime = start; */ /* Use first frame start time */
						}
						//if(i==4)frameMin = atof(str);
						//if(i==5)frameMax = atof(str);
						if(i==1)decayCor = atof(str);	/* decay correction to remove */
						
						if(k==istart-1)decayCor_first = decayCor;

						str = strtok( NULL, delims );	/* next delimited token */
						i++;				/* column counter */
					}
					
					if (duration > 0){
						durationTotal += duration;	/* running total */
					}
                    }	/* if k==i */
                    j++;
			}	/* while fgets */
			rewind(recfp);
		
			for (i = 0; i < dimension; i++) {				/* process and sum the pixels */
			
				if (decayCor > 0)  image3d[i] /= decayCor;		/* remove decay correction */
				if (duration > 0)  image3d[i] *= duration;		/* scale by frame duration seconds */
			
				img[i] += image3d[i];
			
			}
			frameCounter++;

		}  /* if k>= istart */
	}  /* for k=0 */
	
/***********************************************/
/* Calculate decay correction for summed image */
/***********************************************/
        decayCor = 1;
	if (halflife > 0){
	
		dc = 0.693147 / halflife;					/* decay constant = log(2)/halflife */	
		numerator = durationTotal * dc;
		right = 1 - exp((-1.0 * dc ) * durationTotal);
		left = exp((-1.0 * dc) * startTime);
		
		decayCor = numerator / (left * right);
		
	}
	if (USEFIRST==1)decayCor = decayCor_first;

	printf("sum_pet_4dfp: frameCount=%d halflife=%.2f sec startTime=%.2f sec durationTotal=%.2f sec decayCor=%.5f\n",\
		        frameCounter-1,halflife,startTime,durationTotal,decayCor);
/********************/
/* final processing */
/********************/
	for (i = 0; i < dimension; i++) {
		   if (durationTotal > 0) img[i] /= durationTotal;		/* reverse the duration scaleing */
		   if (halflife > 0)      img[i] *= decayCor;			/* scale by the new decay correction */
		   if (scaleFactor != 1.0)img[i] *= scaleFactor;		/* final scalefactor */
	}
	
	fprintf (stdout, "Writing: %s\n", outfile);
	if (ewrite (img, dimension, control, fp_out)) errw (program, outfile);
	
	fclose (recfp);
	fclose (fp_img);
	fclose (fp_out);
	
/*******************/
/* create rec file */
/*******************/
	sprintf (recfile, "%s.rec", imgfile);
	exists_oldrec = !access (recfile, R_OK);
	if (exists_oldrec) {
		sprintf  (command, "/bin/cp %s.rec %s.rec0", imgfile, imgfile);	status |= system (command);
	}
	
	startrece (outfile, argc, argv, rcsid, control);
		sprintf  (command, "Summed Volumes: %d to %d\n", istart, iend); printrec (command);
	
	if (halflife != 0.0) {
		sprintf  (command, "Half-life used to correct for decay: %.2f\nCorrection Applied: %f\n", halflife, decayCor); printrec (command);
        }
        if (halflife <= 0.0) {
		sprintf  (command, "Decay correction removed: half-life: %f\n", halflife); printrec (command);
        }
	if (scaleFactor != 1.0) {
		sprintf  (command, "Each pixel scaled after summing: %f\n", scaleFactor); printrec (command);
	}
	
	if (exists_oldrec) {
		sprintf  (command, "cat %s.rec0 >> %s.rec",  imgfile, outfile);	status |= system (command);
		sprintf  (command, "/bin/rm %s.rec0", imgfile);			status |= system (command);
		if (status) {
			fprintf (stderr, "%s: %s.rec create error\n", program, outfile);
		}
	} else {
		sprintf (command, "%s not found\n", recfile); printrec (command);
	}
	endrec ();


/***************/
/* ifh and hdr */
/***************/

	ifh.matrix_size[3] = 1;
	if (Writeifh (program, outfile, &ifh, control)) errw (program, outfile);
		sprintf (command, "ifh2hdr %s", outroot); printf ("%s\n", command);
		status = system (command);
	
	free (img);
	free (image3d);
	exit (status);
}

