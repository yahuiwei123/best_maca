#!/bin/bash
set -e
set -x
# Requirements for this script
#  installed versions of: FSL5.0.1 or higher (including python with numpy, needed to run aff2rigid - part of FSL)
#  environment: FSLDIR

################################################ SUPPORT FUNCTIONS ##################################################

Usage() {
  echo "`basename $0`: Tool for creating a 6 DOF alignment of the AC, ACPC line and hemispheric plane in MNI space"
  echo " "
  echo "Usage: `basename $0` --workingdir=<working dir> --in=<input image> --ref=<reference image> --out=<output image> --omat=<output matrix> [--brainsize=<brainsize>]"
}

# function for parsing options
getopt1() {
    sopt="$1"
    shift 1
    for fn in $@ ; do
	if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
	    echo $fn | sed "s/^${sopt}=//"
	    return 0
	fi
    done
}

defaultopt() {
    echo $1
}

################################################### OUTPUT FILES #####################################################

# All except $Output variables, are saved in the Working Directory:
#     roi2full.mat, full2roi.mat, roi2std.mat, full2std.mat
#     robustroi.nii.gz  (the result of the initial cropping)
#     acpc_final.nii.gz (the 12 DOF registration result)
#     "$OutputMatrix"  (a 6 DOF mapping from the original image to the ACPC aligned version)
#     "$Output"  (the ACPC aligned image)

################################################## OPTION PARSING #####################################################

# Just give usage if no arguments specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi
# check for correct options
if [ $# -lt 5 ] ; then Usage; exit 1; fi

# parse arguments
WD=`getopt1 "--workingdir" $@`  # "$1"
Input=`getopt1 "--in" $@`  # "$2"
Reference=`getopt1 "--ref" $@`  # "$3"
Output=`getopt1 "--out" $@`  # "$4"
OutputMatrix=`getopt1 "--omat" $@`  # "$5"
BrainSizeOpt=`getopt1 "--brainsize" $@`  # "$6"

# default parameters
Reference=`defaultopt ${Reference} ${FSLDIR}/data/standard/MNI152_T1_1mm`
Output=`$FSLDIR/bin/remove_ext $Output`
WD=`defaultopt $WD ${Output}.wdir`

# make optional arguments truly optional  (as -b without a following argument would crash robustfov)
if [ X${BrainSizeOpt} != X ] ; then BrainSizeOpt="-b ${BrainSizeOpt}" ; fi

echo " "
echo " START: ACPCAlignment"

mkdir -p $WD

# Record the input options in a log file
echo "$0 $@" >> $WD/log.txt
echo "PWD = `pwd`" >> $WD/log.txt
echo "date: `date`" >> $WD/log.txt
echo " " >> $WD/log.txt

########################################## DO WORK ##########################################

# # Crop the FOV
# ${FSLDIR}/bin/robustfov -i "$Input" -m "$WD"/roi2full.mat -r "$WD"/robustroi.nii.gz $BrainSizeOpt

# # Invert the matrix (to get full FOV to ROI)
# ${FSLDIR}/bin/convert_xfm -omat "$WD"/full2roi.mat -inverse "$WD"/roi2full.mat

# # Test if pre-brain mask exists
# if [ `${FSLDIR}/bin/imtest ${Input}_brain` = 1 ] ; then
#         echo "Found ${Input}_brain.nii.gz. Use ${Input}_brain for init registration"
#         ${FSLDIR}/bin/flirt -in "$Input"_brain -ref "$WD"/robustroi.nii.gz -applyxfm -init "$WD"/full2roi.mat -out "$WD"/robustroi.nii.gz # Inserted by Takuya Hayashi, 24th Oct 2015
# else
#         echo "Not found ${Input}_brain.nii.gz. Use $Input for init registration"
# fi


# Register cropped image to MNI152 (6 DOF)
${FSLDIR}/bin/flirt -interp spline -in "$WD"/robustroi.nii.gz -ref "$Reference" -omat "$WD"/roi2std.mat -out "$WD"/acpc_final.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -dof 6
# Registration functions
doRegister() {
	# Initialization
	antsRegistration -d 3 --float 1 -r [${trg}, ${mov} , 0] -t Rigid[0.1] \
	--winsorize-image-intensities [0.005, 0.995] \
	-m MI[${trg}, ${mov}, 1, 32] -c 0 -f 4 -s 2 \
	-o [${regBase}_init, ${regBase}_init.nii.gz] -v

	# Rigid registration. using the initialization
	antsRegistration --dimensionality 3 --float 1 \
	--interpolation Linear \
	--winsorize-image-intensities [0.005, 0.995] \
	--use-histogram-matching 1 \
	--transform Rigid[1.5] \
	--metric MI[${trg},${regBase}_init.nii.gz,1,32,Regular,0.3] \
	--convergence [1000x500x250x100,1e-7,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output [${regBase}_rigid, ${regBase}_rigid.nii.gz] \
	--v

    # Combine all transforms so far to create an initial transform for the nonlinear registration
	antsApplyTransforms --dimensionality 3 \
	--input ${mov} --reference-image ${trg} \
	--output Linear[${regBase}_rigid.mat] \
	--interpolation Linear \
	--transform ${regBase}_rigid0GenericAffine.mat \
	--transform ${regBase}_init0GenericAffine.mat \
	--v
}

register_one_step() {

	echo
	echo Starting one-step registration.
	echo
	
	# Get sizes of the volumes
	mri_binarize --count size_mov.txt --i ${mov} --min 0.001 
	mri_binarize --count size_trg.txt --i ${trg} --min 0.001 
	vol_mov=$(awk '{print $(NF-2)}' size_mov.txt)
	vol_trg=$(awk '{print $(NF-2)}' size_trg.txt)
	rm size_mov.txt
	rm size_trg.txt
	movBase="${mov##*/}"
	trgBase="${trg##*/}"
	
	# Register movable volume to talairach volume directly.
	# This may work well if both volumes have approximately the same size, resolution, and anatomy.
	echo
	echo Step 1:
	echo Registering movable volume to talairach volume.
	echo
	
	if (( $(echo "${vol_trg} > ${vol_mov}" | bc -l) )) # if trg is larger than mov
	then
		mov=${mov}
		trg=${trg}
		regBase="${OUTPUT_DIR}"/"${movBase%%.*}"_to_"${trgBase%%.*}"
        echo $mov $trg
		doRegister
	else
        tmp=${mov}
		mov=${trg}
		trg=${tmp}
		regBase="${OUTPUT_DIR}"/"${movBase%%.*}"_to_"${trgBase%%.*}"
        echo $mov $trg
		doRegister

	fi	

	# Combine the transforms
	if (( $(echo "${vol_trg} > ${vol_mov}" | bc -l) )) # if trg is larger than mov
	then

		echo
		echo Combining warp from mov to NMT and warp from NMT to talairach.
		echo

		# Movable is smaller than trg
		# Combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output Linear[${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform ${regBase}_rigid.mat \
		--v

	else

		echo
		echo Combining inverse warp from trg to mov and warp from NMT to talairach
		echo
		
		# Movable is larger than trg
		# Invert the second transform here since we were going from NMT to movable
		# Combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output Linear[${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform [${regBase}_rigid.mat, 1] \
		--v

	fi

}

# prepare some varibles
mov=${Input}.nii.gz
trg=${Reference}
OUTPUT_DIR=${WD}
movBase=`basename -s .nii.gz ${mov}`
trgBase=`basename -s .nii.gz ${trg}`
finalTransformLin="${OUTPUT_DIR}"/rigid

# Do the registrations
register_one_step;

# Apply the transforms to check accuracy of transforms
# Linear transform
antsApplyTransforms --dimensionality 3 --float 1 \
--input ${mov} \
--reference-image ${trg} \
--output ${Output}.nii.gz \
--interpolation Linear \
--transform ${finalTransformLin}.mat \
--v


# Register pre-brain mask
if [ `${FSLDIR}/bin/imtest ${Input}_brain` = 1 ] ; then
    fslmaths "$Input"_brain -thr 0.1 -bin "$Input"_brain_mask
    ${FSLDIR}/bin/applywarp --rel --interp=nn -i "$Input"_brain_mask -r "$Reference" --premat="$OutputMatrix" -o "$Output"_brain_mask # Inserted by Takuya Hayashi
    fslmaths "$Output" -mas "$Output"_brain_mask "$Output"_brain
fi


mv $WD/rigid.mat $OutputMatrix
# echo Removed:
rm -v $WD/*_0_*


echo " "
echo " END: ACPCAlignment"
echo " END: `date`" >> $WD/log.txt

########################################## QA STUFF ##########################################

if [ -e $WD/qa.txt ] ; then rm -f $WD/qa.txt ; fi
echo "cd `pwd`" >> $WD/qa.txt
echo "# Check that the following image does not cut off any brain tissue" >> $WD/qa.txt
echo "fslview $WD/robustroi" >> $WD/qa.txt
echo "# Check that the alignment to the reference image is acceptable (the top/last image is spline interpolated)" >> $WD/qa.txt
echo "fslview $Reference $WD/acpc_final $Output" >> $WD/qa.txt

##############################################################################################
