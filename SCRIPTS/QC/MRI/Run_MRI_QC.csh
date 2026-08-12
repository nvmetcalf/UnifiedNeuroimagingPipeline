#!/bin/csh

source $1 
source $2

set SubjectHome = $cwd

if(! -e QC) mkdir QC

$PP_SCRIPTS/QC/MRI/Run_fMRI_Movement_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/Compute_tSNR.csh $1 $2
if($status) exit 1

#$PP_SCRIPTS/QC/MRI/Create_GrayPlots.csh $1 $2
#if($status) exit 1

$PP_SCRIPTS/QC/MRI/Compute_Surface_Homotopic_Lag.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/Compute_SD.csh $1 $2
if($status) exit 1

