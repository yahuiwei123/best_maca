#!/bin/bash 
set -e
set -x
echo " "
echo " START: T2w2T1Reg"

##### Revise begin.
# edit by yhwei
# Use ANTs to register T2w to T1w instead fsl
##### Revise end.

WD="$1"
T1wImage="$2"
T1wImageBrain="$3"
T2wImage="$4"
T2wImageBrain="$5"
OutputT1wImage="$6"
OutputT1wImageBrain="$7"
OutputT1wTransform="$8"
OutputT2wImage="$9"
OutputT2wTransform="${10}"

T1wImageBrainFile=`basename "$T1wImageBrain"`

# prepare some varibles
mov=${T2wImageBrain}
trg=${T1wImageBrain}
OUTPUT_DIR=${WD}
movBase="${mov##*/}"
trgBase="${trg##*/}"

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
	--metric MI[${trg},${regBase}_init.nii.gz,1,32,Regular,0.25] \
	--convergence [1000x500x250x100,1e-7,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output [${regBase}_rigid, ${regBase}_rigid.nii.gz] \
	--v

	# Affine registration
	antsRegistration --dimensionality 3 --float 1 \
	--interpolation Linear \
	--winsorize-image-intensities [0.005, 0.995] \
	--use-histogram-matching 1 \
	--transform Affine[0.1] \
	--metric MI[${trg},${regBase}_rigid.nii.gz,1,32,Regular,0.25] \
	--convergence [1000x500x250x100,1e-7,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output [${regBase}_affine, ${regBase}_affine.nii.gz] \
	--v

	# Combine all transforms so far to create an initial transform for the nonlinear registration
	antsApplyTransforms --dimensionality 3 \
	--input ${mov} --reference-image ${trg} \
	--output Linear[${regBase}_linear.mat] \
	--interpolation Linear \
	--transform ${regBase}_affine0GenericAffine.mat \
	--transform ${regBase}_rigid0GenericAffine.mat \
	--transform ${regBase}_init0GenericAffine.mat \
	--v

    # Nonlinear registration using affine as initial transform
	antsRegistration --dimensionality 3 --float 1 \
	--interpolation Linear \
	--winsorize-image-intensities [0.005, 0.995] \
	--use-histogram-matching 1 \
	--initial-moving-transform ${regBase}_linear.mat \
	--transform SyN[0.2,3,0] \
	--metric CC[${trg}, ${mov},1,4] \
	--convergence [100x70x50x20,1e-6,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output ${regBase}_nonlinear \
	--v

	# Apply the transform
	antsApplyTransforms --dimensionality 3 --float 1 \
	--input ${mov} --reference-image ${trg} \
	--output [${regBase}.nii.gz, 1] \
	--interpolation Linear \
	--transform ${regBase}_nonlinear1Warp.nii.gz \
	--transform ${regBase}_nonlinear0GenericAffine.mat \
	--v

	# Check that the displacement field is correct
	antsApplyTransforms --dimensionality 3 --float 1 \
	--input ${mov} --reference-image ${trg} \
	--output ${regBase}_warped.nii.gz \
	--interpolation Linear \
	--transform ${regBase}.nii.gz \
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

		doRegister
	else
		tmp=${mov}
		mov=${trg}
		trg=${tmp}
		regBase="${OUTPUT_DIR}"/"${movBase%%.*}"_to_"${trgBase%%.*}"

		doRegister

	fi	

	# Combine the transforms
	if (( $(echo "${vol_trg} > ${vol_mov}" | bc -l) )) # if trg is larger than mov
	then

		echo
		echo Combining warp from mov to NMT and warp from NMT to talairach.
		echo

		# Movable is smaller than trg
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output [${finalTransformNonLin}.nii.gz, 1] \
		--interpolation Linear \
		--transform ${regBase}_nonlinear1Warp.nii.gz \
		--transform ${regBase}_nonlinear0GenericAffine.mat \
		--v

		# Also combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output Linear[${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform ${regBase}_linear.mat \
		--v

	else

		echo
		echo Combining inverse warp from trg to mov and warp from NMT to talairach
		echo
		
		# Movable is larger than trg
		# Invert the second transform here since we were going from NMT to movable
        antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output [${finalTransformNonLin}.nii.gz, 1] \
		--interpolation Linear \
		--transform [${regBase}_nonlinear0GenericAffine.mat, 1] \
		--transform ${regBase}_nonlinear1InverseWarp.nii.gz \
		--v

		# Also combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${trg} \
		--output Linear[${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform [${regBase}_linear.mat, 1] \
		--v

	fi

}

finalTransformLin="${OUTPUT_DIR}"/linear
finalTransformNonLin="${OUTPUT_DIR}"/nonlinear

# Do the registrations
register_one_step;

# echo Removed:
# rm -v ${regBase}*

# Apply the transforms to check accuracy of transforms
# Linear transform
antsApplyTransforms --dimensionality 3 --float 1 \
--input ${mov} --reference-image ${trg} \
--output "${OUTPUT_DIR}/${movBase%%.*}"_to_"${trgBase%%.*}"_linear.nii.gz \
--interpolation Linear \
--transform ${finalTransformLin}.mat \
--v

# Nonlinear transform
antsApplyTransforms --dimensionality 3 --float 1 \
--input "${OUTPUT_DIR}/${movBase%%.*}"_to_"${trgBase%%.*}"_linear.nii.gz \
--reference-image ${trg} \
--output "${OUTPUT_DIR}/${movBase%%.*}"_to_"${trgBase%%.*}"_nonlinear.nii.gz \
--interpolation Linear \
--transform ${finalTransformNonLin}.nii.gz \
--v

mv "${OUTPUT_DIR}/${movBase%%.*}"_to_"${trgBase%%.*}"_nonlinear.nii.gz "$OUTPUT_DIR"/T2w2T1w.nii.gz
mv ${finalTransformLin}.mat "${OUTPUT_DIR}"/T2w2T1w.mat

# convert ANTs .mat file into FSL .mat format
c3d_affine_tool -ref ${trg} -src ${mov} -itk "${OUTPUT_DIR}"/T2w2T1w.mat -ras2fsl -o flirt.mat
# wb_command -convert-affine -from-itk "${OUTPUT_DIR}"/T2w2T1w.mat -to-flirt "${OUTPUT_DIR}"/flirt.nii.gz ${mov} ${trg}
wb_command -convert-warpfield -from-itk ${finalTransformNonLin}.nii.gz -to-fnirt "${OUTPUT_DIR}"/fnirt.nii.gz ${mov}
cp "$OUTPUT_DIR"/T2w2T1w.nii.gz "$OutputT2wImage".nii.gz
${FSLDIR}/bin/convertwarp --relout --rel -r "$OutputT2wImage".nii.gz -w "${OUTPUT_DIR}"/fnirt.nii.gz --postmat="${OUTPUT_DIR}"/flirt.mat --out="$OutputT2wTransform"

# cp "$T1wImageBrain".nii.gz "$WD"/"$T1wImageBrainFile".nii.gz
# ${FSLDIR}/bin/epi_reg --epi="$T2wImageBrain" --t1="$T1wImage" --t1brain="$WD"/"$T1wImageBrainFile" --out="$WD"/T2w2T1w
# ${FSLDIR}/bin/applywarp --rel --interp=spline --in="$T2wImage" --ref="$T1wImage" --premat="$WD"/T2w2T1w.mat --out="$WD"/T2w2T1w
# ${FSLDIR}/bin/fslmaths "$WD"/T2w2T1w -add 1 "$WD"/T2w2T1w -odt float
# cp "$T1wImage".nii.gz "$OutputT1wImage".nii.gz
# cp "$T1wImageBrain".nii.gz "$OutputT1wImageBrain".nii.gz
# ${FSLDIR}/bin/fslmerge -t $OutputT1wTransform "$T1wImage".nii.gz "$T1wImage".nii.gz "$T1wImage".nii.gz
# ${FSLDIR}/bin/fslmaths $OutputT1wTransform -mul 0 $OutputT1wTransform
# cp "$WD"/T2w2T1w.nii.gz "$OutputT2wImage".nii.gz
# ${FSLDIR}/bin/convertwarp --relout --rel -r "$OutputT2wImage".nii.gz -w $OutputT1wTransform --postmat="$WD"/T2w2T1w.mat --out="$OutputT2wTransform"

echo " "
echo " START: T2w2T1Reg"
