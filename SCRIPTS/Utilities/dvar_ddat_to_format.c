#include<stdio.h>
#include<stdlib.h>
#include<math.h>
#include<string.h>

int main(int argc, char *argv[])
{
	int iArgCount = 1;
	char *sArguements = NULL;

	/* File pointer for reading in dvar formats, ddat files, and vals files*/
	char *sFileName = NULL;
	FILE *FileBeingRead = NULL;

	/*general purpose character buffer*/
	char *sBuffer = malloc(sizeof(char) * 4096);
	strcpy(sBuffer,"\0");

	/*boolean arrays that store the formats*/
	int *bDVARFormat = NULL;
	int *bDDATFormat = NULL;

	/*used to perform the forward and backward frame removal on ddat formats*/
	int *bCopy = NULL;

	/*the index of the column being read*/
	unsigned int iColumn = 0;

	double dDisplacementValue = 0.0;

	/*
	DDAT threshold, should be user specified. Otherwise this should be
	big enough to make a "blank" format
	*/
	double dThreshold = 100.0;

	/*Number of frames in the respective formats*/
	unsigned int iDVARFrames = 0;
	unsigned int iDDATFrames = 0;

	/*Used for reading in files*/
	char iTemp = '\0';
	char iPrevious = ' ';

	/*
	Flag to use AND logic for including frames.
	if 1 and 0 then 0. if 1 and 1 then 1
	*/
		int bUseAND = 1;

		/*
		Flag to output the displacement values for the ddat files.
		Only the displacement values will be output
	*/
		int bOutputDDATValues = 0;

	/*
		Number of frames forward and backward to exclude when
		a bad ddat frame is found.
	*/
	unsigned int iBackwards = 0;
	unsigned int iForwards = 0;

	/*pi... tasty tasty pi...*/
	const double pi = atan2(1,0) * 2;

	/* default number of frames to skip per run */
		int iFramesToSkip = 4;

	/*What to threshold the vals */
		float fDVARThreshold = 1000.0f;

	/*number of runs of DDAT*/
		int iDDATRuns = 0;

	/*Number of frames per DDAT run*/
		int iFrameArray[99] = {0};

		/*Frame index of the current run*/
		int iFramesThisRun = 0;

	unsigned int iRunMaxFrames = 0;
	int iFramesToBeSkipped = 0;

	int Run = 0;
	unsigned int f = 0;
		unsigned int i = 0;

		if(argc > 1)
		{
			/*run through the command line and see whats invoked*/
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

					bDVARFormat = malloc(sizeof(int) * 4096);

				FileBeingRead = NULL;
					FileBeingRead = fopen(sFileName, "rb");
					if(FileBeingRead == NULL)
					{
						printf("DVAR Error reading %s!\n",sFileName);
					return 0;
					}
					else
					{
					strcpy(sBuffer,"\0");

					while((iTemp = (char)fgetc(FileBeingRead)) != EOF )
					strcat(sBuffer,&iTemp);

					expandf(sBuffer,4096);

					iDVARFrames = strlen(sBuffer);  /*number of frames the DVAR format has*/

					for(f = 0; f < iDVARFrames; ++f)
					bDVARFormat[f] = (sBuffer[f] == '+' ? 1 : 0);
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

				if(fDVARThreshold == 0)
				{
					printf("\nPlease specify a dvar threshold before invoking -v");
					return 0;
				}
				sFileName = argv[iArgCount + 1];
					bDVARFormat = malloc(sizeof(int) * 4096);

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
						bDVARFormat[iDVARFrames] = atof(sBuffer) < fDVARThreshold ? 1 : 0;
						++iDVARFrames;
						strcpy(sBuffer,"\0");   /*clear the buffer*/
					}
					else
						strcat(sBuffer,&iTemp);
					}
					}
				}
				else if(sArguements[0] == '-'
				&& sArguements[1] == 't')
				{

				if(iArgCount + 1 < argc && atof(argv[iArgCount + 1]) != 0)
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
				if(iArgCount + 1 < argc && atof(argv[iArgCount + 1]) != 0)
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
				bUseAND = 0;
			}
			else if(sArguements[0] == '-'
				&& sArguements[1] == 'j')
			{
				--iArgCount;
				bOutputDDATValues = 1;
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
					bDDATFormat = malloc(sizeof(int) * 4096);
					}

					f = iFramesToSkip;

					while((iTemp = (char)fgetc(FileBeingRead)) != EOF)
					{
					if(iTemp == '#')	/*see if it's a line we don't care about*/
					{
						while((iTemp = (char)fgetc(FileBeingRead)) != '\n' && iTemp != EOF);	/*burn off the line*/
					}
					else    /*should be a valid line*/
					{
						strcpy(sBuffer, "\0");  /*clear the buffer*/
						i = 0; /*reset the buffer index*/
						iPrevious = ' ';    /*reset the previously read character*/
						iColumn = 0;    /*reset the column we are on*/
						dDisplacementValue = 0; /*reset the displacement value*/

						/*now we need to read the line and parse it as we go*/
						while((iTemp = (char)fgetc(FileBeingRead)) != '\n' && iTemp != EOF )
						{
							if(iTemp != ' ')
							{
								sBuffer[i] = iTemp;
								++i;
								sBuffer[i] = '\0';
							}
							else if(iTemp == ' ' && iPrevious != ' ' && iColumn > 0 && iColumn < 7)
							{
								if(iColumn > 3)
								{
									dDisplacementValue += fabs((atof(sBuffer) * ((pi)/180)) * 50);    /* convert the degrees to linear distance in mm*/
								}
								else
								{
									dDisplacementValue += fabs(atof(sBuffer));  /*linear distance in mm*/
								}

								i = 0; /*resets the buffer as we have that columns number*/
								iColumn++;
							}
							else if(iTemp == ' ' && iPrevious != ' ' && iColumn == 0)
							{
								i = 0; /*this is only to skip the first column*/
								++iColumn;
							}
							iPrevious = iTemp;
						}

						if(iTemp == '\n')
						{
							if(f > 0)
								--f;

							bDDATFormat[iDDATFrames] = (dDisplacementValue < dThreshold && dDisplacementValue > 0 && f == 0? 1 : 0);

							if(bOutputDDATValues)
								printf("%f\n", dDisplacementValue);

							if(dDisplacementValue == 0)
							{
								f = iFramesToSkip;
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

		printf("\n\r-t = Designate a threshold for DDAT data files (may have decimal points).");

		printf("\n\r-o = Use OR logic to determine if a frame should be included in the \n\t\tderived format. Default is AND logic.");

		printf("\n\r-b = How many frames backwards should be marked as \"bad\" when \n\t\ta bad frame is found in the ddat format.");
		printf("\n\r-f = How many frames forwards should be marked as \"bad\" when \n\t\ta bad frame is found in the ddat format.");
		printf("\n\r-j = Output DDAT displacement values. No format is created.");

		printf("\n\r-s = Number of Frames to skip per run. Default is 4.");

		printf("\n\rDDAT files must be from the same bold runs that the DVAR format \n\t\trepresents AND must be in the same order!");
		printf("\n\nUsage:");
		printf("\ndvar_ddat_to_format -d mydvarformat.format -f 1 -t 0.05 bold_1.ddat bold_2.ddat ... bold_n.ddat");
		printf("\n\n\r=================================================\n\n\r");
		return 0;
	}
		/*
			check to make sure that we have the same number of BOLD frames in each format.
			were counted up as they were read in
		*/

	/* Quit if we were just outputing the DDAT displacement values */

	if(bOutputDDATValues)
		return 0;

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

	bCopy = malloc(sizeof(int) * iDDATFrames);    /*create a copy of the ddat format to work in*/

	for(i = 0; i < iDDATFrames; ++i)
		bCopy[i] = bDDATFormat[i];

	f = 0;
	/*go run by run and exclude frames base on forward and backwards skip*/
	for(Run = 1; Run <= iDDATRuns; ++Run)
	{
		/*the frame index of the end of the current run*/
		iRunMaxFrames += iFrameArray[Run];
		iFramesToBeSkipped = iFramesToSkip;
		/*skip the first 4 (or user specified) frames*/
		while(iFramesToBeSkipped > 0 )
		{
			--iFramesToBeSkipped;
			bCopy[f] = 0;
			++f;
		}

		/*now to go through the frames and go forward and backward on each set of bad data*/
		while(f < iRunMaxFrames)
		{
			/*
				There should be 3 cases:
					Previous index is good, this one is bad, and the next one is bad - ignore backward
					Previous is Bad, this one is bad, and the next is good - ignore forward
					Previous is good, this is bad, and the next is good. - ignore both ways
			*/

			if(bDDATFormat[f - 1] && !bDDATFormat[f] && !bDDATFormat[f+1])
			{
				/*while we have frames to ignore going backwards and we do not back into the previous run*/
				for(i = 1; i <= iBackwards && (f - i) > (unsigned)(iRunMaxFrames - iFrameArray[Run]);++i)
				{
					bCopy[f - i] = 0;
				}
			}
			else if(!bDDATFormat[f - 1] && !bDDATFormat[f] && bDDATFormat[f+1])
			{
				for(i = 1; i <= iForwards && (f + i) <= (unsigned)iRunMaxFrames;++i)
				{
					bCopy[f + i] = 0;
				}
			}
			else if(bDDATFormat[f - 1] && !bDDATFormat[f] && bDDATFormat[f+1])
			{
				for(i = 1; i<=iBackwards && (f - i) > (unsigned)(iRunMaxFrames - iFrameArray[Run]);++i)
				{
					bCopy[f - i] = 0;
				}
				for(i = 1; i<=iForwards && (f + i) <= (unsigned)iRunMaxFrames;++i)
				{
					bCopy[f + i] = 0;
				}
			}
			++f;
		}
	}

	/*
		destroy the old format
		and keep the new one
	*/
	free(bDDATFormat);
	bDDATFormat = bCopy;
	bCopy = NULL;

	/*allocates the appropriate amount of space for the derived buffer*/
	free(sBuffer);
	sBuffer = malloc(sizeof(char) * (iDDATFrames-1));

	/*
		derive the new format if we did not output the ddat timecourse
	*/
	i = 0;
	if(bDVARFormat == NULL)
	{
		/*there is no dvar format, so only the ddat format will be used*/
		while(i < iDDATFrames)
		{
			sBuffer[i] = (bDDATFormat[i] ? '+' : 'x');
			++i;
		}
	}
	else
	{
		while(i < iDDATFrames)
		{
			if(bUseAND)
				sBuffer[i] = (bDDATFormat[i] && bDVARFormat[i] ? '+' : 'x');
			else
				sBuffer[i] = (bDDATFormat[i] || bDVARFormat[i] ? '+' : 'x');
			++i;
		}
	}
	/*output the format*/
	printf("%s", sBuffer);

	/*clean up after the dirty deed*/
	free(sBuffer);
	free(bDVARFormat);
	free(bDDATFormat);
	return 0;
}

