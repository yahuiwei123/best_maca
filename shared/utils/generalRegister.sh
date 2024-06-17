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
-r	target volume (the space to be registered to).
-m	mode (rigid, affine, nonlinear transform to be apply).
-l	loss function (MI, CC).

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
while getopts ":i:o:w:r:m:ch" opt; do
  case $opt in
    i) mov=${OPTARG};;
    o) OUTPUT_DIR=${OPTARG};;
	w) WORK_DIR=${OPTARG};;
    r) trg=${OPTARG};;
    m) mode=${OPTARG};;
	l) loss=${OPTARG};;
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
elif [ "x" == "x$mov" ]; then
    echo "-i [movable] input is required"
    exit 1
elif [ "x" == "x$OUTPUT_DIR" ]; then
    echo "-o [WORK_DIR] input is required"
    exit 
elif [ "x" == "x$WORK_DIR" ]; then
    echo "-w [WORK_DIR] input is required"
    exit 1
elif [ "x" == "x$trg" ]; then
    echo "-r [target] input is required"
    exit 1
elif [ "x" == "x$mode" ]; then
    echo "-m [mode] input is required"
    exit 1
elif [ "x" == "x$loss" ]; then
    echo "-m [loss function] input is required"
    exit 1
elif [ "x" == "x$(which antsRegistration)" ]; then
  echo "Could not find ANTs"
  exit 1
fi

echo "
Running registerTalairach with the following parameters:
- input volume: 			${mov}
- output directory: 		${OUTPUT_DIR}
- work directory: 			${WORK_DIR}
- reference volume: 		${trg}
- register mode:            ${mode}
- loss function:			${loss}
"

if [[ clean_up -eq 1 ]]
then
	echo "- clean-up:				yes"
else
	echo "- clean-up:				no"
fi

# Rigid register functions
doRigid() {
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
	--transform Rigid[0.25] \
	--metric MI[${trg},${mov},1,32,Regular,0.25] \
	--convergence [500,1e-7,10] \
	--shrink-factors 2 \
	--smoothing-sigmas 1vox \
	--output [${regBase}_rigid, ${regBase}_rigid.nii.gz] \
	--v
}

doAffine() {
    # Affine registration using affine obtain by {doRidid} as initial transform
	antsRegistration --dimensionality 3 --float 1 \
	--interpolation Linear \
	--winsorize-image-intensities [0.005, 0.995] \
	--use-histogram-matching 1 \
	--transform Affine[0.25] \
	--metric MI[${trg},${regBase}_rigid.nii.gz,1,32,Regular,0.25] \
	--convergence [1000x500x250x100,1e-7,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output [${regBase}_affine, ${regBase}_affine.nii.gz] \
	--v
}

doNonlinear() {
    # Nonlinear registration using affine obtain by {doRidid, doAffine} as initial transform
	antsRegistration --dimensionality 3 --float 1 \
	--interpolation Linear \
	--winsorize-image-intensities [0.005, 0.995] \
	--use-histogram-matching 1 \
	--initial-moving-transform ${regBase}_linear.mat \
	--transform SyN[0.25,3,0] \
	--metric MI[${trg}, ${mov},1,32,Regular,0.25] \
	--convergence [100x70x50x20,1e-6,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output ${regBase}_nonlinear \
	--v
}

# Registration functions
doRegister() {
    if [ "$mode" = "rigid" ] ; then
        doRigid;
		
        # Combine all transforms so far to create an initial transform for the nonlinear registration
        antsApplyTransforms --dimensionality 3 \
        --input ${mov} --reference-image ${trg} \
        --output Linear[${regBase}_linear.mat] \
        --interpolation Linear \
        --transform ${regBase}_rigid0GenericAffine.mat \
        --transform ${regBase}_init0GenericAffine.mat \
        --v
    fi

    if [ "$mode" = "affine" ] ; then
        doRigid;
        doAffine;

        # Combine all transforms so far to create an initial transform for the nonlinear registration
        antsApplyTransforms --dimensionality 3 \
        --input ${mov} --reference-image ${trg} \
        --output Linear[${regBase}_linear.mat] \
        --interpolation Linear \
        --transform ${regBase}_affine0GenericAffine.mat \
        --transform ${regBase}_rigid0GenericAffine.mat \
        --transform ${regBase}_init0GenericAffine.mat \
        --v
    fi


    if [ "$mode" = "nonlinear" ] ; then
		doRigid;
        doAffine;
		doNonlinear;

        # Combine all transforms so far to create an initial transform for the nonlinear registration
        antsApplyTransforms --dimensionality 3 \
        --input ${mov} --reference-image ${trg} \
        --output Linear[${regBase}_linear.mat] \
        --interpolation Linear \
        --transform ${regBase}_affine0GenericAffine.mat \
        --transform ${regBase}_rigid0GenericAffine.mat \
        --transform ${regBase}_init0GenericAffine.mat \
        --v

		# Apply the transform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output [${regBase}.nii.gz, 1] \
		--interpolation Linear \
		--transform ${regBase}_nonlinear1Warp.nii.gz \
		--transform ${regBase}_nonlinear0GenericAffine.mat \
		--v
    fi
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
	
	# Register movable volume to talairach volume directly.
	# This may work well if both volumes have approximately the same size, resolution, and anatomy.
	echo
	echo Step 1:
	echo Registering movable volume to talairach volume.
	echo
	
	if (( $(echo "${vol_trg} > ${vol_mov}" | bc -l) )) # if nmt is larger than mov
	then
		mov=${mov}
		trg=${trg}
		regBase="${WORK_DIR}"/"${movBase}"_to_"${trgBase}"

		doRegister;
	else
		tmp=${mov}
		mov=${trg}
		trg=${tmp}
		regBase="${WORK_DIR}"/"${movBase}"_to_"${trgBase}"

		doRegister;

		tmp=${mov}
		mov=${trg}
		trg=${tmp}
	fi	

	# Combine the transforms
	if (( $(echo "${vol_trg} > ${vol_mov}" | bc -l) )) # if NMT is larger than mov
	then

		echo
		echo Combining warp from mov to NMT and warp from NMT to talairach.
		echo

		# Movable is smaller than NMT
        if [ "$mode" = "nonlinear" ] ; then
            antsApplyTransforms --dimensionality 3 --float 1 \
            --input ${mov} --reference-image ${trg} \
            --output [${WORK_DIR}/${finalTransformNonLin}.nii.gz, 1] \
            --interpolation Linear \
            --transform ${regBase}_nonlinear1Warp.nii.gz \
            --transform ${regBase}_nonlinear0GenericAffine.mat \
            --v

            # Apply transform to movable volume
			antsApplyTransforms --dimensionality 3 --float 1 \
			--input ${mov} --reference-image ${trg} \
			--output ${regBase}_final.nii.gz \
			--interpolation Linear \
			--transform ${WORK_DIR}/${finalTransformNonLin}.nii.gz \
			--v
        fi

		# Also combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output Linear[${WORK_DIR}/${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform ${regBase}_linear.mat \
		--v

		# Apply transform to movable volume
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output ${regBase}_final.nii.gz \
		--interpolation Linear \
		--transform ${WORK_DIR}/${finalTransformLin}.mat \
		--v

	else

		echo
		echo Combining inverse warp from NMT to mov and warp from NMT to talairach
		echo
		
		# Movable is larger than NMT
		# Invert the second transform here since we were going from NMT to movable
        if [ "$mode" = "nonlinear" ] ; then
            antsApplyTransforms --dimensionality 3 --float 1 \
            --input ${mov} --reference-image ${trg} \
            --output [${WORK_DIR}/${finalTransformNonLin}.nii.gz, 1] \
            --interpolation Linear \
            --transform [${regBase}_nonlinear0GenericAffine.mat, 1] \
            --transform ${regBase}_nonlinear1InverseWarp.nii.gz \
            --v

			# Apply transform to movable volume
			antsApplyTransforms --dimensionality 3 --float 1 \
			--input ${mov} --reference-image ${trg} \
			--output ${regBase}_final.nii.gz \
			--interpolation Linear \
			--transform ${WORK_DIR}/${finalTransformNonLin}.nii.gz \
			--v
        fi

		# Also combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output Linear[${WORK_DIR}/${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform [${regBase}_linear.mat, 1] \
		--v

		# Apply transform to movable volume
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output ${regBase}_final.nii.gz \
		--interpolation Linear \
		--transform ${WORK_DIR}/${finalTransformLin}.mat \
		--v

	fi
}

finalTransformLin=linear
finalTransformNonLin=nonlinear
movBase=`basename ${mov}`
movBase=${movBase%%.*}
trgBase=`basename ${trg}`
trgBase=${trgBase%%.*}

# Setup directory
mkdir -p $WORK_DIR
mkdir -p $OUTPUT_DIR

# Do the registrations
register_one_step;

# Restore result
mv ${regBase}_final.nii.gz $OUTPUT_DIR

# Clean up work dir
if [ "${clean_up}" -eq 1 ]
then
	echo Removed:
	rm -rv ${WORK_DIR}/${regBase}*
fi

echo
echo register done.
echo

return `basename ${regBase}_final.nii.gz`

