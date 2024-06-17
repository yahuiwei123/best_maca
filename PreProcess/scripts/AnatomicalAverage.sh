#!/bin/bash
set -e

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
    i) mov=${OPTARG};;
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
    bnm=`basename $bnm`;
    cp $fn $WORK_DIR/$bnm
    newimlist="$newimlist $WORK_DIR/$bnm"
done

if [ $verbose = yes ] ; then echo "Images: $imagelist  Output: $output"; fi

# for each image reorient, register to std space, (optionally do "get transformed FOV and crop it based on this")
for fn in $newimlist ; do
  $FSLDIR/bin/fslreorient2std ${fn}.nii.gz ${fn}_reorient
  $FSLDIR/bin/robustfov -i ${fn}_reorient -r ${fn}_roi -m ${fn}_roi2orig.mat $BrainSizeOpt
  $FSLDIR/bin/convert_xfm -omat ${fn}TOroi.mat -inverse ${fn}_roi2orig.mat
  $FSLDIR/bin/flirt -in ${fn}_roi -ref "$StandardImage" -omat ${fn}roi_to_std.mat -out ${fn}roi_to_std -dof 12 -searchrx -30 30 -searchry -30 30 -searchrz -30 30
  $FSLDIR/bin/convert_xfm -omat ${fn}_std2roi.mat -inverse ${fn}roi_to_std.mat
done

# register images together, using standard space brain masks
im1=`echo $newimlist | awk '{ print $1 }'`;
for im2 in $newimlist ; do
    if [ $im2 != $im1 ] ; then
        # register version of two images (whole heads still)
	    ${HCPPIPEDIR}/shared/utils/generalRegister.sh -i $im2 -o $OUTPUT_DIR -w $WORK_DIR -r $im1 -m affine -c
    else
	    cp $FSLDIR/etc/flirtsch/ident.mat ${im1}_to_im1_linmask.mat
    fi
done

# get the halfway space transforms (midtrans output is the *template* to halfway transform)
translist=""
for fn in $newimlist ; do translist="$translist ${fn}_to_im1_linmask.mat" ; done
$FSLDIR/bin/midtrans --separate=${WORK_DIR}/ToHalfTrans --template=${im1}_roi $translist

# interpolate
n=1;
for fn in $newimlist ; do
    num=`$FSLDIR/bin/zeropad $n 4`;
    n=`echo $n + 1 | bc`;
    if [ $crop = yes ] ; then
	$FSLDIR/bin/applywarp --rel -i ${fn}_roi --premat=${WORK_DIR}/ToHalfTrans${num}.mat -r ${im1}_roi -o ${WORK_DIR}/ImToHalf${num} --interp=spline
    else
	$FSLDIR/bin/convert_xfm -omat ${WORK_DIR}/ToHalfTrans${num}.mat -concat ${WORK_DIR}/ToHalfTrans${num}.mat ${fn}TOroi.mat
	$FSLDIR/bin/convert_xfm -omat ${WORK_DIR}/ToHalfTrans${num}.mat -concat ${im1}_roi2orig.mat ${WORK_DIR}/ToHalfTrans${num}.mat
	$FSLDIR/bin/applywarp --rel -i ${fn}_reorient --premat=${WORK_DIR}/ToHalfTrans${num}.mat -r ${im1}_reorient -o ${WORK_DIR}/ImToHalf${num} --interp=spline  
    fi
done
# average outputs
comm=`echo ${WORK_DIR}/ImToHalf* | sed "s@ ${WORK_DIR}/ImToHalf@ -add ${WORK_DIR}/ImToHalf@g"`;
tot=`echo ${WORK_DIR}/ImToHalf* | wc -w`;
$FSLDIR/bin/fslmaths ${comm} -div $tot ${output}



# CLEANUP
if [ $cleanup != no ] ; then
    # the following protects the rm -rf call (making sure that it is not null and really is a directory)
    if [ X$WORK_DIR != X ] ; then
	if [ -d $WORK_DIR ] ; then
	    # should be safe to call here without trying to remove . or $HOME or /
	    rm -rf $WORK_DIR
	fi
    fi
fi

