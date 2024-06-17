#!/bin/bash
set -e
set -x
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
while getopts ":i:o:w:ch" opt; do
  case $opt in
    i) imlist=${OPTARG};;
    o) OUTPUT_DIR=${OPTARG};;
    w) WORK_DIR=${OPTARG};;
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
elif [ "x" == "x$imlist" ]; then
    echo "-i [movable] input is required"
    exit 1
elif [ "x" == "x$OUTPUT_DIR" ]; then
    echo "-o [OUTPUT_DIR] input is required"
    exit 1
elif [ "x" == "x$WORK_DIR" ]; then
    echo "-r [WORK_DIR] input is required"
    exit 1
fi

echo "
Running registerTalairach with the following parameters:
- image list: 			    ${imlist}
- output directory: 		${OUTPUT_DIR}
- work directory:    		${WORK_DIR}
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

# process imagelist
newimlist=""
for fn in $imlist ; do
    bnm=`basename $fn`;
    cp $fn $WORK_DIR/$bnm
    newimlist="$newimlist $WORK_DIR/$bnm"
done

# register images together
im1=`echo $newimlist | awk '{ print $1 }'`;
translist="${im1}"

for im2 in $newimlist ; do
    if [ $im2 != $im1 ] ; then
        # register version of two images (whole heads still)
	    ${HCPPIPEDIR}/shared/utils/generalRegister.sh -i $im2 -o $OUTPUT_DIR -w $WORK_DIR -r $im1 -m affine -l MI -c
        echo $?
        translist="$? ${translist}"
    fi
done

# average outputs
bnm=`basename $im1`
bnm=${bnm%%.*}
fslmerge -t ${OUTPUT_DIR}/${bnm}_merged.nii.gz $translist
fslmaths ${OUTPUT_DIR}/${bnm}_merged.nii.gz -Tmean ${OUTPUT_DIR}/${bnm}_merged.nii.gz

# Clean up work dir
if [ "${clean_up}" -eq 1 ]
then
	echo Removed:
	rm -rv ${WORK_DIR}
fi

