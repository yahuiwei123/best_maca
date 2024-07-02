#!/bin/bash
set -e
set -x
# Some default parameters
func="fsl"
clean_up=0

# Help message
usage () {
echo "
=== generalRegister ===

This script provides a general robust registration function for 
rigid, affine, nonlinear transform. The registration combines ANTs
and FSL for best performance.

Usage:
sh generalRegister.sh -i [movable] -o [output directory] -w [work directory] -r [target] -m [mode] -l [loss function] [-c]

Required arguments:
-i	input volume (to be registered, needs to be skullstripped).
-o	output directory (e.g. ${subject}/mri/transforms).
-w  work directory
-r	target volume (the space to be registered to).
-m	mode (rigid, affine, nonlinear transform to be apply).
-l	loss function (MI, CC).

Optional arguments
-f  linear registration function (ants or fsl). Default: fsl.
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
while getopts ":i:o:w:r:m:l:f:ch" opt; do
  case $opt in
    i) mov=${OPTARG};;
    o) OUTPUT_DIR=${OPTARG};;
	w) WORK_DIR=${OPTARG};;
    r) trg=${OPTARG};;
    m) mode=${OPTARG};;
	l) loss=${OPTARG};;
	f) func=${OPTARG};;
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
elif [ "x" == "x$func" ]; then
    echo "-m [register func] input is required"
    exit 1
elif [ "x" == "x$(which antsRegistration)" ]; then
  echo "Could not find ANTs"
  exit 1
elif [ "x" == "x$(which flirt)" ]; then
  echo "Could not find FSL"
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
- register function:		${func}
"

if [[ clean_up -eq 1 ]]
then
	echo "- clean-up:				yes"
else
	echo "- clean-up:				no"
fi

# Rigid register functions
doRigid() {
	if [[ "$func" == "ants" ]]
	then
		# Initialization (ANTs)
		antsRegistration -d 3 --float 1 -r [${trg}, ${mov} , 0] -t Rigid[0.1] \
		--winsorize-image-intensities [0.005, 0.995] \
		-m MI[${trg}, ${mov}, 1, 32] -c 0 -f 4 -s 2 \
		-o [${regBase}_init, ${regBase}_init.nii.gz] -v

		# Rigid registration. using the initialization (ANTs)
		antsRegistration --dimensionality 3 --float 1 \
		--interpolation Linear \
		--winsorize-image-intensities [0.005, 0.995] \
		--use-histogram-matching 1 \
		--transform Rigid[0.25] \
		--metric MI[${trg}, ${regBase}_init.nii.gz, 1, 32, Regular, 0.2] \
		--convergence [1000x500x250x100, 1e-7, 10] \
		--shrink-factors 8x4x2x1 \
		--smoothing-sigmas 3x2x1x0vox \
		--output [${regBase}_rigid, ${regBase}_rigid.nii.gz] \
		--v
	elif [[ "$func" == "fsl" ]]
	then
		# Initialization (FLIRT)
		flirt -in ${mov} \
		-ref ${trg} \
		-out ${regBase}_init.nii.gz \
		-omat ${regBase}_init0GenericAffine.mat \
		-dof 6

		# Rigid registration. using the initialization (FLIRT)
		flirt -in ${regBase}_init.nii.gz \
		-ref ${trg} \
		-out ${regBase}_rigid.nii.gz \
		-omat ${regBase}_rigid0GenericAffine.mat \
		-dof 6
	else
		echo "Registration function ${func} is not valid!"
		exit 0
	fi
}

doAffine() {
	if [[ "$func" == "ants" ]]
	then
		# Affine registration using affine obtain by {doRidid} as initial transform (ANTs)
		antsRegistration --dimensionality 3 --float 1 \
		--interpolation Linear \
		--winsorize-image-intensities [0.005, 0.995] \
		--use-histogram-matching 1 \
		--transform Affine[0.25] \
		--metric MI[${trg}, ${regBase}_rigid.nii.gz, 1, 32, Regular, 0.25] \
		--convergence [1000x500x250x100, 1e-7, 10] \
		--shrink-factors 8x4x2x1 \
		--smoothing-sigmas 3x2x1x0vox \
		--output [${regBase}_affine, ${regBase}_affine.nii.gz] \
		--v
	elif [[ "$func" == "fsl" ]]
	then
		# Affine registration using affine obtain by {doRidid} as initial transform (FLIRT)
		flirt -in ${regBase}_rigid.nii.gz \
		-ref ${trg} \
		-out ${regBase}_affine.nii.gz \
		-omat ${regBase}_affine0GenericAffine.mat \
		-dof 9
	else
		echo "Registration function ${func} is not valid!"
		exit 0
	fi
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
		if [[ "$func" == "fsl" ]]
		then
			wb_command -convert-affine \
			-from-flirt \
				${regBase}_init0GenericAffine.mat \
				${mov} ${trg} \
			-to-itk \
				${regBase}_init0GenericAffine.mat

			wb_command -convert-affine \
			-from-flirt \
				${regBase}_rigid0GenericAffine.mat \
				${regBase}_init.nii.gz ${trg} \
			-to-itk \
				${regBase}_rigid0GenericAffine.mat
		fi

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

		if [[ "$func" == "fsl" ]]
		then
			wb_command -convert-affine \
			-from-flirt \
				${regBase}_init0GenericAffine.mat \
				${mov} ${trg} \
			-to-itk \
				${regBase}_init0GenericAffine.mat

			wb_command -convert-affine \
			-from-flirt \
				${regBase}_rigid0GenericAffine.mat \
				${regBase}_init.nii.gz ${trg} \
			-to-itk \
				${regBase}_rigid0GenericAffine.mat
		fi

		doAffine;

		if [[ "$func" == "fsl" ]]
		then
			wb_command -convert-affine \
			-from-flirt \
				${regBase}_affine0GenericAffine.mat \
				${regBase}_rigid.nii.gz ${trg} \
			-to-itk \
				${regBase}_affine0GenericAffine.mat
		fi

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

		# Combine all transforms so far to create an initial transform for the nonlinear registration
        antsApplyTransforms --dimensionality 3 \
        --input ${mov} --reference-image ${trg} \
        --output Linear[${regBase}_linear.mat] \
        --interpolation Linear \
        --transform ${regBase}_affine0GenericAffine.mat \
        --transform ${regBase}_rigid0GenericAffine.mat \
        --transform ${regBase}_init0GenericAffine.mat \
        --v

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

		# Obtain name of registration file
		movBase=`basename ${mov}`
		movBase=${movBase%%.*}
		trgBase=`basename ${trg}`
		trgBase=${trgBase%%.*}
		regBase="${WORK_DIR}"/"${movBase}"_to_"${trgBase}"

		doRegister;
	else
		# Exchange mov and trg
		tmp=${mov}
		mov=${trg}
		trg=${tmp}

		# Obtain name of registration file
		movBase=`basename ${mov}`
		movBase=${movBase%%.*}
		trgBase=`basename ${trg}`
		trgBase=${trgBase%%.*}
		regBase="${WORK_DIR}"/"${movBase}"_to_"${trgBase}"

		doRegister;
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
            --output [${OUTPUT_DIR}/${finalTransformNonLin}.nii.gz, 1] \
            --interpolation Linear \
            --transform ${regBase}_nonlinear1Warp.nii.gz \
            --transform ${regBase}_nonlinear0GenericAffine.mat \
            --v

            # Apply transform to movable volume
			antsApplyTransforms --dimensionality 3 --float 1 \
			--input ${mov} --reference-image ${trg} \
			--output ${WORK_DIR}/final.nii.gz \
			--interpolation Linear \
			--transform ${OUTPUT_DIR}/${finalTransformNonLin}.nii.gz \
			--v
        fi
		

		# Also combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output Linear[${OUTPUT_DIR}/${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform ${regBase}_linear.mat \
		--v

		# Apply transform to movable volume
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output ${WORK_DIR}/final.nii.gz \
		--interpolation Linear \
		--transform ${OUTPUT_DIR}/${finalTransformLin}.mat \
		--v

	else

		echo
		echo Combining inverse warp from NMT to mov and warp from NMT to talairach
		echo
		
		# swap back
		tmp=${mov}
		mov=${trg}
		trg=${tmp}

		# Movable is larger than NMT
		# Invert the second transform here since we were going from NMT to movable
        if [ "$mode" = "nonlinear" ] ; then
            antsApplyTransforms --dimensionality 3 --float 1 \
            --input ${mov} --reference-image ${trg} \
            --output [${OUTPUT_DIR}/${finalTransformNonLin}.nii.gz, 1] \
            --interpolation Linear \
            --transform [${regBase}_nonlinear0GenericAffine.mat, 1] \
            --transform ${regBase}_nonlinear1InverseWarp.nii.gz \
            --v

			# Apply transform to movable volume
			antsApplyTransforms --dimensionality 3 --float 1 \
			--input ${mov} --reference-image ${trg} \
			--output ${WORK_DIR}/final.nii.gz \
			--interpolation Linear \
			--transform ${OUTPUT_DIR}/${finalTransformNonLin}.nii.gz \
			--v
        fi

		# Also combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output Linear[${OUTPUT_DIR}/${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform [${regBase}_linear.mat, 1] \
		--v

		# Apply transform to movable volume
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output ${WORK_DIR}/final.nii.gz \
		--interpolation Linear \
		--transform ${OUTPUT_DIR}/${finalTransformLin}.mat \
		--v

	fi
}

finalTransformLin=linear
finalTransformNonLin=nonlinear

# Setup directory
mkdir -p $WORK_DIR
mkdir -p $OUTPUT_DIR

# Crop and pad template to generate a robust template for registraion
read xmin xsize ymin ysize zmin zsize _ _ <<< $(fslstats ${trg} -w)
fslroi ${trg} ${WORK_DIR}/template.nii.gz $xmin $xsize $ymin $ysize $zmin $zsize
if [ -e ${WORK_DIR}/`basename ${trg}`]
then
	rm ${WORK_DIR}/`basename ${trg}`
fi
3dZeropad -RL 256 -AP 256 -IS 256 -prefix ${WORK_DIR}/`basename ${trg}` ${WORK_DIR}/template.nii.gz
rm ${WORK_DIR}/template.nii.gz
trg=${WORK_DIR}/`basename ${trg}`

# Do the registrations
register_one_step;

rm ${WORK_DIR}/`basename ${trg}`

# Restore result
if [ "${WORK_DIR}" != "${OUTPUT_DIR}" ]
then
	mv -f ${WORK_DIR}/final.nii.gz $OUTPUT_DIR
fi

# Clean up work dir
if [ "${clean_up}" -eq 1 ]
then
	echo Removed:
	rm -rv ${WORK_DIR}
fi

echo
echo register done.
echo

exit 0