#!/bin/bash
set -e
set -x
# default parameters
trg=$T1wTemplateBrain
clean_up=0

################################################ SUPPORT FUNCTIONS ##################################################

# Help message
usage () {
echo "
=== generalRegister ===

This script provides an alternative to FreeSurfer's -talairach, 
-gcareg, and -careg steps. It uses antsRegistration to create a linear
affine (talairach.xfm and talairach.lta) and a nonlinear 
(talairach.m3z) warp to Talairach space.

Usage:
sh MacaqueReg.sh -i [movable] -o [output directory] -g [gca file path] -r [registration stages] [-c]

Required arguments:
-i	input volume (to be registered, needs to be skullstripped).
-o	output directory (e.g. ${subject}/mri/transforms).
-r	target volume (the space to be registered to)
-m  mode (rigid, affine, nonlinear transform to be apply)
-l  loss function (MI, CC)

Optional arguments
-c	clean up intermediate files. Include this flag to remove some 
	intermediate files (saves disk space). Default: off.
-h 	display this help message.

For the two- and three-step registrations, pre-calculated warps can be
used (e.g. from chimpanzee to Talairach or from NMT to Talairach) to
save computational time. The script will automatically skip these
steps if existing warps are found in the output directory.
"

}

# Parse arguments
while getopts ":w:i:r:o:a:ch" opt; do
  case $opt in
	w) WORK_DIR=${OPTARG};;
    i) mov=${OPTARG};;
	r) trg=${OPTARG};;
    o) OUTPUT_DIR=${OPTARG};;
	a) XFM_DIR=${OPTARG};;
    c) clean_up=1;;
    h)
	  usage
	  exit 1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  	:)
      echo "Option -$OPTARG requires an argument" >&2
      exit 1
      ;;
  esac
done

# Check that required parameters, paths, and folders are set
if ((OPTIND == 1))
then
    usage; exit 1
elif [ "x" == "x$WORK_DIR" ]; then
    echo "-w [WORK_DIR] input is required"
    exit 1
elif [ "x" == "x$mov" ]; then
    echo "-i [T2w] input is required"
    exit 1
elif [ "x" == "x$trg" ]; then
    echo "-r [T1w] input is required"
    exit 1
elif [ "x" == "x$OUTPUT_DIR" ]; then
    echo "-o [OUTPUT_DIR] input is required"
    exit 1
elif [ "x" == "x$XFM_DIR" ]; then
    echo "-o [XFM_DIR] input is required"
    exit 1
fi

echo "
Running registerTalairach with the following parameters:
- work directory:    		${WORK_DIR}
- T2w image: 			    ${mov}
- T1w image:	    		${trg}
- output directory: 		${OUTPUT_DIR}
- xfm directory: 			${XFM_DIR}
"

if [[ clean_up -eq 1 ]]
then
	echo "- clean-up:				yes"
else
	echo "- clean-up:				no"
fi

# setup directory
mkdir -p $OUTPUT_DIR
mkdir -p $WORK_DIR
mkdir -p $XFM_DIR


echo " "
echo " START: ACPCAlignment"

# Record the input options in a log file
echo "$0 $@" >> $WORK_DIR/log.txt
echo "PWD = `pwd`" >> $WORK_DIR/log.txt
echo "date: `date`" >> $WORK_DIR/log.txt
echo " " >> $WORK_DIR/log.txt

########################################## DO WORK ##########################################
if [[ clean_up -eq 1 ]]
then
	sh $HCPPIPEDIR_Shared/utils/generalRegister.sh -i $mov -w $WORK_DIR -r $trg -o $OUTPUT_DIR -m rigid -l MI -f ants -c
else
	sh $HCPPIPEDIR_Shared/utils/generalRegister.sh -i $mov -w $WORK_DIR -r $trg -o $OUTPUT_DIR -m rigid -l MI -f ants
fi

movBase=`basename ${mov}`
movBase=${movBase%%.*}

echo ${OUTPUT_DIR}
mv -f ${OUTPUT_DIR}/linear.mat ${XFM_DIR}/acpc.mat
mv -f ${OUTPUT_DIR}/final.nii.gz ${OUTPUT_DIR}/${movBase}_acpc.nii.gz

# Obtain new brain mask
fslmaths ${OUTPUT_DIR}/${movBase}_acpc.nii.gz -bin ${OUTPUT_DIR}/${movBase}_acpc_brain_mask.nii.gz


echo " "
echo " END: ACPCAlignment"
echo " END: `date`" >> $WORK_DIR/log.txt

########################################## QA STUFF ##########################################

if [ -e $WORK_DIR/qa.txt ] ; then rm -f $WORK_DIR/qa.txt ; fi
echo "cd `pwd`" >> $WORK_DIR/qa.txt
echo "# Check that the alignment to the reference image is acceptable (the top/last image is spline interpolated)" >> $WORK_DIR/qa.txt
echo "freeview -v $trg ${OUTPUT_DIR}/${movBase}_acpc.nii.gz" >> $WORK_DIR/qa.txt

##############################################################################################
