#include<stdio.h>
#include<stdlib.h>
#include<math.h>
#include<string.h>
#include<ctype.h>

int expandf (char *strin, int len) {
	char	*stringt, *string;	/* buffers */
	char	*lp;			/* left delimeter */
	char	*np;			/* ascii digit */
	char	*rp;			/* right delimiter */
	char	ascnum[16];
	char	c2[2];
	int	c, i, k, l;
	int	len2;
	int	level;
	int	num;
	int	status;
	int	debug = 0;

	if (!strlen (strin)) return 0;
	status = 0;
	memset (c2, '\0', 2);
	len2 = len * 2;
	stringt = (char *) calloc (len2 + 1, sizeof (char));
	string  = (char *) calloc (len2 + 1, sizeof (char));
	if (!stringt || !string) {
		fprintf (stderr, "expandf: memory allocation error\n");
		exit (-1);
	}
	if (debug) printf ("expandf: len=%d\n", len);

/***************************/
/* squeeze out white space */
/***************************/
	rp = strin;
	lp = string;
	while (c = *rp++) if (!isspace (c)) *lp++ = c;
	*lp = '\0';	/* safety */
	if (debug) {l = strlen (string); printf ("%s\t%d\n", string, l);}

/****************************/
/* expand sinusoidal epochs */
/****************************/
	rp = stringt;			/* expansion buffer */
	lp = string;			/* input string */
	stringt[len2] = '\xff';		/* write stop barrier */
	while (c = *lp++) {
		switch (c) {
		case 'C': case 'c': case 'S': case 's':
			np = ascnum;
			k = 0;
			while (k < 16 && isdigit (*lp)) {
				*np++ = *lp++;
				k++;
			}
			*np = '\0';
			k = atoi (ascnum) - 1;
			*rp++ = '(';			if (*rp == '\xff') goto ABORT;
			for (i = 0; i < k; i++) {
				*rp++ = c;		if (*rp == '\xff') goto ABORT;
			}
			*rp++ = '~';			if (*rp == '\xff') goto ABORT;
			*rp++ = ')';			if (*rp == '\xff') goto ABORT;
			break;
		default:
			*rp++ = c;			if (*rp == '\xff') goto ABORT;
			break;
		}
	}
	*lp = '\0';	/* safety */
	stringt[len2] = '\0';				/* remove write stop barrier */
	strncpy (string, stringt, len2);
	if (debug) {l = strlen (string); printf ("%s\t%d\n", string, l);}

/**********************/
/* expand parentheses */
/**********************/
	level = 0;
	while (rp = strrchr (string, ')')) {
		*rp = '\0';
		lp = rp;
		while (lp > string && isdigit (c = *(lp - 1))) *--lp = '\0';
		level++;
		while ((level > 0) && (lp > string)) {
			lp--;
			if (*lp == ')') level++;
			if (*lp == '(') level--;
		}
		if (level) {
			printf ("expandf error: unbalanced parentheses\n");
			status = 1; goto DONE;
		}
		*lp = '\0';
		num = 1;
		np = lp;
		while (np > string && isdigit (c = *(np - 1))) np--;
		if (strlen (np) > 0) {
			num = atoi (np);		/* printf ("num=%d\n", num); */
			*np = '\0';
		}
		strncpy (stringt, string, len2);
		if (strlen (stringt) + num*strlen (lp + 1) > len2) goto ABORT;
		for (k = 0; k < num; k++) strcat (stringt, lp + 1);
		if (strlen (stringt) + strlen (rp + 1) > len2) goto ABORT;
		strcat (stringt, rp + 1);
		strncpy (string, stringt, len2);	/* printf ("%s\n", string); */
	}
	if (strrchr (string, '(')) {
		printf ("expandf error: unbalanced parentheses\n");
		status = 1; goto DONE;
	}
	if (debug) {l = strlen (string); printf ("%s\t%d\n", string, l);}

/********************/
/* expand multiples */
/********************/
	while (np = strpbrk (string, "0123456789")) {
		rp = np;
		while (isdigit (c = *++rp));
		strncpy (c2, rp, 1);
		*rp = '\0';
		num = atoi (np);			/* printf ("num=%d\n", num); */
		*np = '\0';
		strncpy (stringt, string, len2);
		if (strlen (stringt) + num > len2) goto ABORT;
		for (k = 0; k < num; k++) strcat (stringt, c2);
		if (strlen (stringt) + strlen (rp + 1) > len2) goto ABORT;
		strcat (stringt, rp + 1);
		strncpy (string, stringt, len2);	/* printf ("%s\n", string); */
	}
	if (debug) {l = strlen (string); printf ("%s\t%d\n", string, l);}

DONE:	l = strlen (string);
	if (l >= len) {
		fprintf (stderr, "expandf error: expanded format length exceeds allocated buffer size (%d)\n", len);
		status = 1;
	}
	string[len - 1] = '\0';
	if (!status) strcpy (strin, string);
	free (string);
	free (stringt);
	return (status);
ABORT:	status = -1;
	goto DONE;
}

int main(int argc, char *argv[])
{
	int iArgCount = 1;
	char *sArguements = NULL;
	char *sFileName = NULL;
	char sBuffer[1024] = {'\0'};
	bool *bDVARFormat = NULL;
	bool *bDDATFormat = NULL;
	unsigned int iColumn = 0;
	double dDisplacementValue = 0.0;
	double dThreshold = 100.0;
	unsigned int iDVARFrames = 0;
	unsigned int iDDATFrames = 0;
	char iTemp = '\0';
	char iPrevious = ' ';
	unsigned int iCount = 0;
	bool bUseAND = true;
	bool bOutputDDATValues = false;
    char *sDerivedBuffer = NULL;
    unsigned int iBackwards = 0;
    unsigned int iForwards = 0;
    FILE *FileBeingRead = NULL;

    double pi = atan2(1,0) * 2;
	char sDVARFormat[4096] = {"\0"};

	int iFramesToSkip = 4;  //default number of frames to skip per run

	float fDVARThreshold = -0.1f;

	int iDVARRuns = 0;
	int iDDATRuns = 0;

	int iFrameArray[99] = {0};
	int iFramesThisRun = 0;

	if(argc > 1)
	{
		//run through the command line and see whats invoked
		while(iArgCount < argc)
		{
			sArguements = argv[iArgCount];

			if(sArguements[0] == '-'
			&& sArguements[1] == 'd')
			{
			    sFileName = argv[iArgCount + 1];

                if(bDVARFormat != NULL)
                {
                    printf("\nDVAR Format already specified!");
                    return 0;
                }

				bDVARFormat = new bool[4096];

                FileBeingRead = NULL;
				FileBeingRead = fopen(sFileName, "rb");
				if(FileBeingRead == NULL)
				{
					printf("DVAR Error reading %s!\n",sFileName);
                    return 0;
				}
				else
				{
                    strcpy(sDVARFormat,"\0");

                    while((iTemp = (char)fgetc(FileBeingRead)) != EOF )
                        strcat(sDVARFormat,&iTemp);

                    expandf(sDVARFormat,4096);

                    iDVARFrames = strlen(sDVARFormat);  //number of frames the DVAR format has
                    //printf("%s\n-\n",sDVARFormat);

                    for(unsigned int f = 0; f < iDVARFrames; ++f)
                        bDVARFormat[f] = (sDVARFormat[f] == '+' ? true : false);
				}
			}
			else if(sArguements[0] == '-'
			&& sArguements[1] == 'v')
			{
                if(bDVARFormat != NULL)
                {
                    printf("\nDVAR Format already specified!");
                    return 0;
                }

                if(fDVARThreshold < 0)
                {
                    printf("\nPlease specify a dvar threshold before invoking -v");
                    return 0;
                }
                sFileName = argv[iArgCount + 1];
				bDVARFormat = new bool[4096];

                FileBeingRead = NULL;
				FileBeingRead = fopen(sFileName, "rb");
				if(FileBeingRead == NULL)
				{
					printf("VALS Error reading %s!\n",sFileName);
                    return 0;
				}
				else
				{
                    strcpy(sBuffer,"\0");
                    while((iTemp = (char)fgetc(FileBeingRead)) != EOF )
                    {
                        if(iTemp == '\n' || iTemp == '\r')
                        {

                            bDVARFormat[iDVARFrames] = atof(sBuffer) < fDVARThreshold ? true : false;

                            ++iDVARFrames;

                            if(atof(sBuffer) == 500)
                                ++iDVARRuns;

                            strcpy(sBuffer,"\0");   //clear the buffer

                        }
                        else
                            strcat(sBuffer,&iTemp);
                    }
				}
			}
			else if(sArguements[0] == '-'
                 && sArguements[1] == 't')
			{

			    if(iArgCount + 1 < argc && atof(argv[iArgCount + 1]) >= 0)
                    dThreshold = atof(argv[iArgCount + 1]);
                else
                {
                    printf("\n\rYou must specify a value for -t!\n");
                    return 0;
                }
			}
			else if(sArguements[0] == '-'
                 && sArguements[1] == 'x')
			{
			    if(iArgCount + 1 < argc && atof(argv[iArgCount + 1]) >= 0)
                {
                    fDVARThreshold = atof(argv[iArgCount + 1]);
                }
                else
                {
                    printf("\n\rYou must specify a value for -x!\n");
                    return 0;
                }
			}
            else if(sArguements[0] == '-'
                 && sArguements[1] == 'o')
            {
                --iArgCount;
                 bUseAND = false;
            }
            else if(sArguements[0] == '-'
                 && sArguements[1] == 'j')
            {
                --iArgCount;
                 bOutputDDATValues = true;
            }
            else if(sArguements[0] == '-'
                 && sArguements[1] == 'b')
            {
                if(iArgCount + 1 < argc && atoi(argv[iArgCount + 1]) != 0)
                {
                    iBackwards = atoi(argv[iArgCount + 1]);
                }
                else
                {
                    printf("\n\rYou must specify a value for -b!\n");
                    return 0;
                }
            }
            else if(sArguements[0] == '-'
                 && sArguements[1] == 's')
            {
                if(iArgCount + 1 < argc && atoi(argv[iArgCount + 1]) != 0)
                {
                    iFramesToSkip = atoi(argv[iArgCount + 1]);
                }
                else
                {
                    printf("\n\rYou must specify a value for -s!\n");
                    return 0;
                }
            }
            else if(sArguements[0] == '-'
                 && sArguements[1] == 'f')
            {
                if(iArgCount + 1 < argc)
                    iForwards = atoi(argv[iArgCount + 1]);
                else
                {
                    printf("\n\rYou must specify a value for -f!\n");
                    return 0;
                }
            }
			else
			{
				sFileName = argv[iArgCount];
				--iArgCount;

                FileBeingRead = NULL;
				FileBeingRead = fopen(sFileName, "rb");
				iFramesThisRun = 0;

				if(FileBeingRead == NULL)
				{
					printf("DDAT Error reading %s!\n",sFileName);
                    return 0;
				}
				else
				{
				    if(bDDATFormat == NULL)
				    {
                        /*
                            we don't know how many frames are in the first run.
                            so make a lot of room. Works in a pinch.
                        */
                        bDDATFormat = new bool[4096];
				    }

                    int iFramesLeftSkip = iFramesToSkip;

                    while((iTemp = (char)fgetc(FileBeingRead)) != EOF)
                    {
                        if(iTemp == '#')	//see if it's a line we don't care about
                        {
                            while((iTemp = (char)fgetc(FileBeingRead)) != '\n' && iTemp != EOF);	//burn off the line
                        }
                        else    //should be a valid line
                        {
                            strcpy(sBuffer, "\0");  //clear the buffer
                            int iIndex = 0; //reset the buffer index
                            iPrevious = ' ';    //reset the previously read character
                            iColumn = 0;    //reset the column we are on
                            dDisplacementValue = 0; //reset the displacement value

                            float fRadius = 0;
                            //now we need to read the line and parse it as we go
                            while((iTemp = (char)fgetc(FileBeingRead)) != '\n' && iTemp != EOF )
                            {
                                if(iTemp != ' ')
                                {
                                    sBuffer[iIndex] = iTemp;
                                    ++iIndex;
                                    sBuffer[iIndex] = '\0';
                                }
                                else if(iTemp == ' ' && iPrevious != ' ' && iColumn > 0 && iColumn < 7)
                                {
                                    if(iColumn > 3)
                                    {
                                        //printf("\n%f : %f : %f",atof(sBuffer) * (pi/180) * 50,fabs(atof(sBuffer) * 0.9), atof(sBuffer) * (pi/180) * sqrt(fRadius));
                                        dDisplacementValue += fabs((atof(sBuffer) * ((pi)/180)) * 50);    // convert the degrees to distance
                                    }
                                    else
                                    {
                                        dDisplacementValue += fabs(atof(sBuffer));
                                        fRadius += pow(atof(sBuffer),2); // this will be the radius of the distance moved
                                    }

                                    iIndex = 0; //resets the buffer as we have that columns number
                                    iColumn++;
                                }
                                else if(iTemp == ' ' && iPrevious != ' ' && iColumn == 0)
                                {
                                    iIndex = 0; //this is only to skip the first column
                                    ++iColumn;
                                }
                                iPrevious = iTemp;
                            }

                            if(iTemp == '\n')
                            {
                                if(iFramesLeftSkip > 0)
                                    --iFramesLeftSkip;

                                bDDATFormat[iDDATFrames] = (dDisplacementValue < dThreshold && dDisplacementValue > 0 && iFramesLeftSkip == 0? true : false);

                                if(bOutputDDATValues)
                                    printf("%f\n", dDisplacementValue);

                                if(dDisplacementValue == 0)
                                {
                                    iFramesLeftSkip = iFramesToSkip;
                                    ++iDDATRuns;
                                }

                                ++iDDATFrames;
                                ++iFramesThisRun;
                            }
                        }
                    }
				}
				if(FileBeingRead != NULL)
                    fclose(FileBeingRead);

                iFrameArray[iDDATRuns] = iFramesThisRun;
			}
			iArgCount += 2;
		}
	}
	else
	{
	    printf("\n\n\r=================================================");
        printf("\n\n\rDVAR DDAT To Format Utility Command-line options");
        printf("\n\r-d = Designate a DVAR format file.");
        printf("\n\r-v = Designate a .vals file to use for DVAR thresholding.");
        printf("\n\r-x = Specify a DVAR Threshold (may have decimal points)");

        printf("\n\r-t = Designate a threshold for DDAT data files.");

        printf("\n\r-o = Use OR logic to determine if a frame should be included in the \n\t\tderived format. Default is AND logic.");

        printf("\n\r-b = How many frames backwards should be marked as \"bad\" when \n\t\ta bad frame is found in the ddat format.");
        printf("\n\r-f = How many frames forwards should be marked as \"bad\" when \n\t\ta bad frame is found in the ddat format.");
        printf("\n\r-j = Output DDAT values. No format is created.");

        printf("\n\r-s = Number of Frames to skip per run");

        printf("\n\rDDAT files must be from the same bold runs that the DVAR format \n\t\trepresents AND must be in the same order!");
        printf("\n\rRandomized formats may only be created on BOLD runs with an equal \n\t\tnumber of frames!");
        printf("\n\nUsage:");
        printf("\ndvar_ddat_to_format -d mydvarformat.format -f 1 -t 0.05 bold_1.ddat bold_2.ddat ... bold_n.ddat");
        printf("\n\n\r=================================================\n\n\r");
        return 0;
    }
	/*
		check to make sure that we have the same number of BOLD frames in each format.
		were counted up as they were read in
	*/

    if(bDDATFormat == NULL)
    {
        printf("\nNo DDAT files specified!\n");
        return 0;
    }

	if(iDDATFrames != iDVARFrames && bDVARFormat != NULL && bDDATFormat != NULL)
	{
		printf("\nNumber of DDAT and DVAR frames differ! \n%i DDAT\n%i DVAR\n", iDDATFrames, iDVARFrames);
		return 0;
	}

	if(bDDATFormat == NULL && bDVARFormat == NULL)
    {
        printf("\n\rNo DVAR or DDAT data specified!\n");
        return 0;
    }

    if(bDDATFormat != NULL)
    {
        bool *bCopy = new bool[iDDATFrames];    //create a copy of the ddat format to work in

        for(unsigned int i = 0; i < iDDATFrames; ++i)
            bCopy[i] = bDDATFormat[i];

        int iRunFrameCount = 0;
        int iRunMaxFrames = 0;
        int iFramesToBeSkipped = 0;

        //go run by run and exclude frames base on forward and backwards skip
        for(int Run = 1; Run <= iDDATRuns; ++Run)
        {
            //the frame index of the end of the current run
            iRunMaxFrames += iFrameArray[Run];

            iFramesToBeSkipped = iFramesToSkip;
            //skip the first 4 (or user specified) frames
            while(iFramesToBeSkipped > 0 )
            {
                --iFramesToBeSkipped;
			 bCopy[iRunFrameCount] = 0;
			if(bDVARFormat != NULL)
				bDVARFormat[iRunFrameCount] = 0;
			
                ++iRunFrameCount;
            }

            //now to go through the frames and go forward and backward on each set of bad data
            while(iRunFrameCount < iRunMaxFrames)
            {
                /*
                    There should be 3 cases:
                        Previous index is good, this one is bad, and the next one is bad - ignore backward
                        Previous is Bad, this one is bad, and the next is good - ignore forward
                        Previous is good, this is bad, and the next is good. - ignore both ways
                */

                if(bDDATFormat[iRunFrameCount - 1] && !bDDATFormat[iRunFrameCount] && !bDDATFormat[iRunFrameCount+1])
                {
                    //while we have frames to ignore going backwards and we do not back into the previous run
                    for(unsigned int i = 1; i <= iBackwards && (iRunFrameCount - i) > (unsigned)(iRunMaxFrames - iFrameArray[Run]);++i)
                    {
                        bCopy[iRunFrameCount - i] = false;
                    }
                }
                else if(!bDDATFormat[iRunFrameCount - 1] && !bDDATFormat[iRunFrameCount] && bDDATFormat[iRunFrameCount+1])
                {
                    for(unsigned int i = 1; i <= iForwards && (iRunFrameCount + i) <= (unsigned)iRunMaxFrames;++i)
                    {
                        bCopy[iRunFrameCount + i] = false;
                    }
                }
                else if(bDDATFormat[iRunFrameCount - 1] && !bDDATFormat[iRunFrameCount] && bDDATFormat[iRunFrameCount+1])
                {
                    for(unsigned int i = 1; i<=iBackwards && (iRunFrameCount - i) > (unsigned)(iRunMaxFrames - iFrameArray[Run]);++i)
                    {
                        bCopy[iRunFrameCount - i] = false;
                    }

                    for(unsigned int i = 1; i<=iForwards && (iRunFrameCount + i) <= (unsigned)iRunMaxFrames;++i)
                    {
                        bCopy[iRunFrameCount + i] = false;
                    }
                }
                ++iRunFrameCount;
            }
        }

        for(unsigned int i = 0; i < iDDATFrames; ++i)
            bDDATFormat[i] = bCopy[i];


        delete []bCopy;

        sDerivedBuffer = new char[iDDATFrames-1];
       
    }
    else
    {
        printf("\n\rThere is no data to work on!\n");
        return 0;
    }

    iCount = 0;
	
	char temp;
	
    //derive the new format if we did not output the ddat timecourse
    //and are not making a random format
    if(!bOutputDDATValues)
    {
        if(bDVARFormat == NULL)
        {
            //there is no dvar format, so only the ddat format will be used
            while(iCount < iDDATFrames)
            {
                //sDerivedBuffer[iCount] = (bDDATFormat[iCount] ? '+' : 'x');
                printf("%c", (bDDATFormat[iCount] ? '+' : 'x'));
                ++iCount;
            }
        }
        else
        {
            while(iCount < iDDATFrames)
            {
                if(bUseAND)
                {
                    //sDerivedBuffer[iCount] = (!bDDATFormat[iCount] && !bDVARFormat[iCount] ? 'x' : '+');
                    printf("%c", (!bDDATFormat[iCount] && !bDVARFormat[iCount] ? 'x' : '+'));
                }
                else
                {
                    //sDerivedBuffer[iCount] = (!bDDATFormat[iCount] || !bDVARFormat[iCount] ? 'x' : '+');
                    printf("%c", (!bDDATFormat[iCount] || !bDVARFormat[iCount] ? 'x' : '+'));
                }
                
                ++iCount;
            }
        }

        //printf("%s", sDerivedBuffer);
    }
    else if(bDDATFormat == NULL && bDVARFormat != NULL) // just output the dvar format...
        printf("%s", sDVARFormat);

    delete []sDerivedBuffer;
    delete []bDVARFormat;
    delete []bDDATFormat;
	return 0;
}

