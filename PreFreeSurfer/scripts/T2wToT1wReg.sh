#!/bin/bash
set -e
set -x
##### Revise begin.
# edit by yhwei
# Use ANTs to register T2w to T1w
##### Revise end.
echo " START: T2w2T1Reg"

# Some default parameters
clean_up=0

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
while getopts ":w:r:i:o:a:ch" opt; do
  case $opt in
	w) WORK_DIR=${OPTARG};;
    r) trg=${OPTARG};;
    i) mov=${OPTARG};;
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
    echo "-r [WORK_DIR] input is required"
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

T1wBase=`basename "$trg"`

# T2w register to T1w
sh ${HCPPIPEDIR_Shared}/utils/generalRegister.sh -i $mov -o $WORK_DIR -w $WORK_DIR -r $trg -m nonlinear -l MI -f ants

# rename nonlinear transform to T2w/T2wToT1wReg/T2w2T1w.nii.gz
mv -f ${WORK_DIR}/nonlinear.nii.gz ${WORK_DIR}/T2w2T1w.nii.gz

# copy some result file to T1w/ and T1w/xfms/
mv -f ${WORK_DIR}/final.nii.gz ${OUTPUT_DIR}/T2w_acpc_dc.nii.gz
cp ${WORK_DIR}/T2w2T1w.nii.gz ${XFM_DIR}/T2w_reg_dc.nii.gz
cp ${trg} ${OUTPUT_DIR}/T1w_acpc_dc.nii.gz

# # convert ANTs .mat file into FSL .mat format
# c3d_affine_tool -ref ${trg} -src ${mov} -itk "${OUTPUT_DIR}"/T2w2T1w.mat -ras2fsl -o flirt.mat
# # wb_command -convert-affine -from-itk "${OUTPUT_DIR}"/T2w2T1w.mat -to-flirt "${OUTPUT_DIR}"/flirt.nii.gz ${mov} ${trg}
# wb_command -convert-warpfield -from-itk ${finalTransformNonLin}.nii.gz -to-fnirt "${OUTPUT_DIR}"/fnirt.nii.gz ${mov}
# cp "$OUTPUT_DIR"/T2w2T1w.nii.gz "$OutputT2wImage".nii.gz
# ${FSLDIR}/bin/convertwarp --relout --rel -r "$OutputT2wImage".nii.gz -w "${OUTPUT_DIR}"/fnirt.nii.gz --postmat="${OUTPUT_DIR}"/flirt.mat --out="$OutputT2wTransform"

# cp "$T1wImageBrain".nii.gz "$WD"/"$T1wImageBrainFile".nii.gz
# ${FSLDIR}/bin/epi_reg --epi="$T2wImageBrain" --t1="$T1wImage" --t1brain="$WD"/"$T1wImageBrainFile" --out="$WD"/T2w2T1w
# ${FSLDIR}/bin/applywarp --rel --interp=spline --in="$T2wImage" --ref="$T1wImage" --premat="$WD"/T2w2T1w.mat --out="$WD"/T2w2T1w
# ${FSLDIR}/bin/fslmaths "$WD"/T2w2T1w -add 1 "$WD"/T2w2T1w -odt float
# cp "$T1wImage".nii.gz "$OutputT1wImage".nii.gz
# ${FSLDIR}/bin/fslmerge -t $OutputT1wTransform "$T1wImage".nii.gz "$T1wImage".nii.gz "$T1wImage".nii.gz
# ${FSLDIR}/bin/fslmaths $OutputT1wTransform -mul 0 $OutputT1wTransform
# cp "$WD"/T2w2T1w.nii.gz "$OutputT2wImage".nii.gz
# ${FSLDIR}/bin/convertwarp --relout --rel -r "$OutputT2wImage".nii.gz -w $OutputT1wTransform --postmat="$WD"/T2w2T1w.mat --out="$OutputT2wTransform"

echo " "
echo " START: T2w2T1Reg"
