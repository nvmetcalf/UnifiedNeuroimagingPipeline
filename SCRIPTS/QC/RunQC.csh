#!/bin/csh

source $1
source $2

$PP_SCRIPTS/QC/MRI/Run_MRI_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/PET/Run_PET_QC.csh $1 $2
if($status) exit 1
