#!/bin/bash 
set -e
set -x

# Requirements for this script
#  installed versions of: FSL5.0.5 or higher , FreeSurfer (version 5.2 or higher) ,
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR 

# make pipeline engine happy...
if [ $# -eq 1 ] ; then
    echo "Version unknown..."
    exit 0
fi

########################################## PIPELINE OVERVIEW ########################################## 

#TODO

########################################## OUTPUT DIRECTORIES ########################################## 

#TODO

# --------------------------------------------------------------------------------
#  Load Function Libraries
# --------------------------------------------------------------------------------

source $HCPPIPEDIR/global/scripts/log.shlib  # Logging related functions
source $HCPPIPEDIR/global/scripts/opts.shlib # Command line option functions

########################################## SUPPORT FUNCTIONS ########################################## 

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

show_usage() {
    echo "Usage information To Be Written"
    exit 1
}

# --------------------------------------------------------------------------------
#   Establish tool name for logging
# --------------------------------------------------------------------------------
log_SetToolName "FreeSurferPipeline.sh"
SPECIES=Macaque
################################################## OPTION PARSING #####################################################

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
    show_usage
fi

log_Msg "Parsing Command Line Options"

# Input Variables
SubjectID=`opts_GetOpt1 "--subject" $@` #FreeSurfer Subject ID Name
SubjectDIR=`opts_GetOpt1 "--subjectDIR" $@` #Location to Put FreeSurfer Subject's Folder
T1wImage=`opts_GetOpt1 "--t1" $@` #T1w FreeSurfer Input for head (Full Resolution)
T1wImageBrain=`opts_GetOpt1 "--t1brain" $@` #T1w FreeSurfer Input for brain (Full Resolution)
T2wImage=`opts_GetOpt1 "--t2" $@` #T2w FreeSurfer Input for brain (Full Resolution)
recon_all_seed=`opts_GetOpt1 "--seed" $@`

#FSLinearTransform=`opts_GetOpt1 "--fslinear" $@`
GCAdir=`opts_GetOpt1 "--gcadir" $@` # Needed for NHP
RescaleVolumeTransform=`opts_GetOpt1 "--rescaletrans" $@` # Needed for NHP
AsegEdit=`opts_GetOpt1 "--asegedit" $@` # Needed to use aseg.edit.mgz 
ControlPoints=`opts_GetOpt1 "--controlpoints" $@` # Needed to use $SubjectID/tmp/control.dat, modified by Takuya Hayashi Nov 2017
WmEdit=`opts_GetOpt1 "--wmedit" $@` # Needed to use wm.edit.mgz, modified by Takuya Hayashi Nov 4th 2015
T2wFlag=`opts_GetOpt1 "--t2wflag" $@` # T2w, FLAIR or NONE for FreeSurferHiresPial.sh, inserted by Takuya Hayashi Nov 4th 2015
SPECIES=`opts_GetOpt1 "--species" $@` # Human, Macaque, Marmoset, inserted by Takuya Hayashi on Feb 13th 2016
IntensityCor=`opts_GetOpt1 "--intensitycor" $@` # NU (default for Human) or FAST (default for NHP) - Methods for intensity correction TH Aug 2019
BrainMasking=`opts_GetOpt1 "--brainmasking" $@` # FS (default for Human) or HCP (default for NHP) - Methods for brain masking TH Aug 2019
RunMode=`opts_GetOpt1 "--runmode" $@`  # Run in step mode (0: run all (default), 1: FSinit, 2: FSaseg, 3: FSNormalize2, 4: FSwhiteandpial, 5: FSfinish)

if [ "$SPECIES" = "" ] ; then SPECIES=Human; fi

if [ "$SPECIES" = "Human" ] ; then GCAdir="${FREESURFER_HOME}/average";fi

# ------------------------------------------------------------------------------
#  Show Command Line Options
# ------------------------------------------------------------------------------

log_Msg "Finished Parsing Command Line Options"
log_Msg "SubjectID: ${SubjectID}"
log_Msg "SubjectDIR: ${SubjectDIR}"
log_Msg "T1wImage: ${T1wImage}"
log_Msg "T1wImageBrain: ${T1wImageBrain}"
log_Msg "T2wImage: ${T2wImage}"
log_Msg "recon_all_seed: ${recon_all_seed}"
log_Msg "GCAdir: ${GCAdir}"
log_Msg "AsegEdit: ${AsegEdit}"
log_Msg "ControlPoints: ${ControlPoints}"
log_Msg "WmEdit: ${WmEdit}"
log_Msg "T2wFlag: ${T2wFlag}"
log_Msg "SPECIES: ${SPECIES}"
log_Msg "IntensityCor method: ${IntensityCor}"
log_Msg "Brain masking method: ${BrainMasking}"
log_Msg "RunMode: ${RunMode}"

# figure out whether to include a random seed generator seed in all the recon-all command lines
seed_cmd_appendix=""
if [ -z "${recon_all_seed}" ] ; then
	seed_cmd_appendix=""
else
	seed_cmd_appendix="-norandomness -rng-seed ${recon_all_seed}"
fi
log_Msg "seed_cmd_appendix: ${seed_cmd_appendix}"

# ------------------------------------------------------------------------------
#  Show Environment Variables
# ------------------------------------------------------------------------------

log_Msg "HCPPIPEDIR: ${HCPPIPEDIR}"
log_Msg "HCPPIPEDIR_FS: ${HCPPIPEDIR_FS}"

# ------------------------------------------------------------------------------
#  Identify Tools
# ------------------------------------------------------------------------------

which_flirt=`which flirt`
flirt_version=`flirt -version`
log_Msg "which flirt: ${which_flirt}"
log_Msg "flirt -version: ${flirt_version}"

which_applywarp=`which applywarp`
log_Msg "which applywarp: ${which_applywarp}"

which_fslstats=`which fslstats`
log_Msg "which fslstats: ${which_fslstats}"

which_fslmaths=`which fslmaths`
log_Msg "which fslmaths: ${which_fslmaths}"

which_recon_all=`which recon-all`
recon_all_version=`recon-all --version`
log_Msg "which recon-all: ${which_recon_all}"
log_Msg "recon-all --version: ${recon_all_version}"

which_mri_convert=`which mri_convert`
log_Msg "which mri_convert: ${which_mri_convert}"

which_mri_em_register=`which mri_em_register`
mri_em_register_version=`mri_em_register --version`
log_Msg "which mri_em_register: ${which_mri_em_register}"
log_Msg "mri_em_register --version: ${mri_em_register_version}"

which_mri_watershed=`which mri_watershed`
mri_watershed_version=`mri_watershed --version`
log_Msg "which mri_watershed: ${which_mri_watershed}"
log_Msg "mri_watershed --version: ${mri_watershed_version}"

# Start work

T1wImageFile=`remove_ext $T1wImage`;
T1wImageBrainFile=`remove_ext $T1wImageBrain`;
T2wImageFile=`remove_ext $T2wImage`;

PipelineScripts=${HCPPIPEDIR_FS}

export SUBJECTS_DIR="$SubjectDIR"

if [ -e "$SubjectDIR"/"$SubjectID"/scripts/IsRunning.lh+rh ] ; then
  rm "$SubjectDIR"/"$SubjectID"/scripts/IsRunning.lh+rh
elif [ -e "$SubjectDIR"/"$SubjectID"_1mm/scripts/IsRunning.lh+rh ] ; then
  rm "$SubjectDIR"/"$SubjectID"_1mm/scripts/IsRunning.lh+rh
fi

# Both the SGE and PBS cluster schedulers use the environment variable NSLOTS to indicate the number of cores
# a job will use.  If this environment variable is set, we will use it to determine the number of cores to
# tell recon-all to use.

NSLOTS=8
if [[ -z ${NSLOTS} ]] ; then
	num_cores=8
else
	num_cores="${NSLOTS}"
fi
log_Msg "num_cores: ${num_cores}"

function runFSinit () {

	log_Msg "Making T1w dim to 256^3 and res to 1mm"
	"$PipelineScripts"/MakeDimto1mm.sh $SPECIES "$T1wImage"
	log_Msg "Making T1w_brain dim to 256^3 and res to 1mm"
	"$PipelineScripts"/MakeDimto1mm.sh $SPECIES "$T1wImageBrain"
	log_Msg "Making T2w dim to 256^3 and res to 1mm"
	"$PipelineScripts"/MakeDimto1mm.sh $SPECIES "$T2wImage"
	Mean=`fslstats $T1wImageBrain -M`
	fslmaths "$T1wImageFile"_1mm.nii.gz -div $Mean -mul 150 -abs "$T1wImageFile"_1mm.nii.gz

	#Initial Recon-all Steps
	if [ -e "$SubjectDIR"/"$SubjectID" ] ; then
		log_Msg "Removing previous FS directory"
 		rm -rf "$SubjectDIR"/"$SubjectID"
	fi
	if [ -e "$SubjectDIR"/"$SubjectID"_1mm ] ; then
		log_Msg "Removing previous FS 1mm directory"
		rm -rf "$SubjectDIR"/"$SubjectID"_1mm
	fi

	log_Msg "Initial recon-all steps"

	recon-all -i "$T1wImageFile"_1mm.nii.gz -subjid $SubjectID -sd $SubjectDIR -motioncor -openmp ${num_cores} ${seed_cmd_appendix}
	# fslmaths "$T1wImageBrainFile"_1mm.nii.gz -add 1 "$SubjectDIR"/"$SubjectID"/mri/brainmask.orig.nii.gz
	# mri_convert "$SubjectDIR"/"$SubjectID"/mri/brainmask.orig.nii.gz "$SubjectDIR"/"$SubjectID"/mri/brainmask.orig.mgz --conform
	mri_convert "$T1wImageBrainFile"_1mm.nii.gz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz --conform  
}


function runNormalize1 () {
	# Intensity Correction use nu_correct for human and fast for NHP
	if [ "$SPECIES" != "Human" ] ; then
		# Added by Haiyan: begin
		reg_stages=3 # three-step registration by default
		export SHARED_DIR=${HCPPIPEDIR}/shared
		cp -rv ${SHARED_DIR}/transforms/* $SubjectDIR/$SubjectID/mri/transforms/
		. ${HCPPIPEDIR}/FreeSurfer/scripts/MacaqueReg.sh \
			-i "$SubjectDIR"/"$SubjectID"/mri/orig.mgz \
			-o "$SubjectDIR"/"$SubjectID"/mri/transforms \
			-g "$GCAdir"/two_times_downsample.gca \
			-r ${reg_stages} -c 2>&1 | tee "$SubjectDIR"/"$SubjectID"/mri/transforms/MacaqueReg.log
		# Added by Haiyan: end

		# Use fast instead of nu_correct (in mri_nu_correct.mni) for bias correction, since the former likely better sharpens the histogram.
        # comment from XL, I think they should be at the same line, or else "ERROR: unknown species"
        commandline=""$SubjectDIR"/"$SubjectID"/mri/orig.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz "$SubjectDIR"/"$SubjectID"/mri/nu.mgz $SPECIES"
        echo $commandline
       	"$PipelineScripts"/IntensityCor.sh "$SubjectDIR"/"$SubjectID"/mri/orig.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz "$SubjectDIR"/"$SubjectID"/mri/nu.mgz $SPECIES
		recon-all -subjid $SubjectID -sd $SubjectDIR -normalization -openmp ${num_cores} ${seed_cmd_appendix}
	else
		# Call recon-all with flags that are part of "-autorecon1", with the exception of -skullstrip.
		# -skullstrip of FreeSurfer not reliable for Phase II data because of poor FreeSurfer mri_em_register registrations with Skull on,
		# so run registration with PreFreeSurfer masked data and then generate brain mask as usual.
		recon-all -subjid $SubjectID -sd $SubjectDIR -talairach -nuintensitycor -normalization -openmp ${num_cores} ${seed_cmd_appendix}   # XL
	fi
}

function runFSbrainmaskandseg () {

	# Generate brain mask
	export OMP_NUM_THREADS=${num_cores}
	if [ ! -e "$SubjectDIR"/"$SubjectID"/mri/brainmask.edit.mgz ] && [ "$BrainMasking" = "FS" ] ; then
		mri_em_register "$SubjectDIR"/"$SubjectID"/mri/nu.mgz "$GCAdir"/RB_all_withskull_2008-03-26.gca \
		"$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull.lta
		mri_watershed -T1 -brain_atlas "$GCAdir"/RB_all_withskull_2008-03-26.gca \
		"$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull.lta "$SubjectDIR"/"$SubjectID"/mri/T1.mgz \
		"$SubjectDIR"/"$SubjectID"/mri/brainmask.auto.mgz
		cp "$SubjectDIR"/"$SubjectID"/mri/brainmask.auto.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz
	elif [ ! -e "$SubjectDIR"/"$SubjectID"/mri/brainmask.edit.mgz ] && [ "$BrainMasking" = "HCP" ] ; then
		cp "$SubjectDIR"/"$SubjectID"/mri/brainmask.orig.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz
	elif  [ -e "$SubjectDIR"/"$SubjectID"/mri/brainmask.edit.mgz ] ; then
		cp "$SubjectDIR"/"$SubjectID"/mri/brainmask.edit.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz 
	else
		cp "$SubjectDIR"/"$SubjectID"/mri/brainmask.orig.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz
	fi
		
	# Registration and normalization to GCA
	log_Msg "Second recon-all steps for registration and normaliztion to GCA"

	recon-all -subjid $SubjectID -sd $SubjectDIR -gcareg -canorm -careg -careginv -rmneck -skull-lta -gca-dir $GCAdir \
	-openmp ${num_cores} ${seed_cmd_appendix}
	cp "$SubjectDIR"/"$SubjectID"/mri/norm.mgz "$SubjectDIR"/"$SubjectID"/mri/norm.orig.mgz 

	log_Msg "Third recon-all steps for segmentation using GCA"
	# Segmentation with GCA
	DIR=`pwd`
	cd "$SubjectDIR"/"$SubjectID"/mri
	if [ "$AsegEdit" = "NONE" ] ; then
		mri_ca_label -align -nobigventricles -nowmsa norm.mgz transforms/talairach.m3z "$GCAdir"/two_times_downsample.gca aseg.auto_noCCseg.mgz
	fi
	cd $DIR
 
}

function runseg () {
        # Registration and normalization to GCA
        log_Msg "Second recon-all steps for registration and normaliztion to GCA"

        # recon-all -subjid $SubjectID -sd $SubjectDIR -gcareg -canorm -careg -careginv -rmneck -skull-lta -gca-dir $GCAdir \
        # -openmp ${num_cores} ${seed_cmd_appendix}
        # cp "$SubjectDIR"/"$SubjectID"/mri/norm.mgz "$SubjectDIR"/"$SubjectID"/mri/norm.orig.mgz

		# Edited by Haiyan: -gcareg, -careg -careginv have been run in MacaqueReg.sh
		cp "$SubjectDIR"/"$SubjectID"/mri/nu.mgz "$SubjectDIR"/"$SubjectID"/mri/nu_noneck.mgz
		recon-all -subjid $SubjectID -sd $SubjectDIR -canorm -gca-dir ${GCAdir} \
			-openmp ${num_cores} ${seed_cmd_appendix}
		cp "$SubjectDIR"/"$SubjectID"/mri/norm.mgz "$SubjectDIR"/"$SubjectID"/mri/norm.orig.mgz


        log_Msg "Third recon-all steps for segmentation using GCA"
        # Segmentation with GCA
        DIR=`pwd`
        cd "$SubjectDIR"/"$SubjectID"/mri
        if [ "$AsegEdit" = "NONE" ] ; then
                mri_ca_label -align -nobigventricles -nowmsa norm.mgz transforms/talairach.m3z "$GCAdir"/two_times_downsample.gca aseg.auto_noCCseg.mgz
        fi
        cd $DIR
}

function runFSaseg () {
	DIR=`pwd`
	cd "$SubjectDIR"/"$SubjectID"/mri
	mri_cc -aseg aseg.auto_noCCseg.mgz -o aseg.auto.mgz -lta "$SubjectDIR"/"$SubjectID"/mri/transforms/cc_up.lta "$SubjectID"
	cp aseg.auto.mgz aseg+claustrum.mgz
	cp aseg.auto.mgz aseg.mgz
	cp aseg.auto.mgz aseg.presurf.mgz
	cd $DIR
}

function runNormalize2 () {
	log_Msg "Fourth recon-all steps for normalization2"
	recon-all -subjid $SubjectID -sd $SubjectDIR -normalization2 -maskbfs
}


# function runNormalize2 () {

# 	log_Msg "Fourth recon-all steps for normalization2"

# 	recon-all -subjid $SubjectID -sd $SubjectDIR -normalization2
# 	#mri_normalize -b 20 -n 5 -aseg "$SubjectDIR"/"$SubjectID"/mri/aseg.mgz -mask "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz \
# 	#"$SubjectDIR"/"$SubjectID"/mri/norm.mgz "$SubjectDIR"/"$SubjectID"/mri/brain.mgz # MH's tuning for pediatric brain

# 	recon-all -subjid $SubjectID -sd $SubjectDIR -maskbfs -segmentation

# 	## Paste claustrum to wm.mgz - Takuya Hayashi, Oct 2017 
# 	DIR=`pwd`
# 	cd "$SubjectDIR"/"$SubjectID"/mri
# 	cp wm.mgz wm.orig.mgz
# 	mri_convert wm.mgz wm.nii.gz
# 	mri_convert aseg+claustrum.mgz aseg+claustrum.nii.gz 
# 	fslmaths aseg+claustrum.nii.gz -thr 138 -uthr 138 -bin -add aseg+claustrum.nii.gz -thr 139 -uthr 139 -bin -mul 250 \
# 	-max wm.nii.gz wm.nii.gz # pasting claustrum to wm.mgz

# 	## deweight cortical gray in wm.mgz to remove prunning of white surface into gray - Takuya Hayahsi Dec 2017
# 	if [[ $ControlPoints = NONE ]] ; then
# 		fslmaths aseg+claustrum.nii.gz -thr 42 -uthr 42 -bin -mul -39 -add aseg+claustrum.nii.gz -thr 3 -uthr 3 \
# 		-bin -s 0.25 -sub 1 -mul -1 -mul wm.nii.gz -thr 50 wm.nii.gz -odt char
# 	fi
# 	## paste wm skeleton for Marmoset - TH Aug 2019
# # YUE ADD
# #	if [[ $SPECIES =~ Marmoset || $SPECIES =~ Macaque ]] ; then
# #		applywarp -i "$GCAdir"/wmskeleton.nii.gz -r ../../T1w_acpc_dc_restore.nii.gz -w \
# #		../../../MNINonLinear/xfms/standard2acpc_dc.nii.gz -o wmskeleton.nii.gz --interp=nn
# #		"$PipelineScripts"/MakeDimto1mm.sh Marmoset wmskeleton.nii.gz
# #		mri_convert -ns 1 -odt uchar wmskeleton_1mm.nii.gz wmskeleton_1mm_conform.nii.gz --conform
# #		fslmaths wmskeleton_1mm_conform.nii.gz -mul 110 -max wm.nii.gz wm.nii.gz
# #	fi
# 	## paste wm lesion when needed
# 	if (( $(imtest ../../../MNINonLinear/WMLesion/wmlesion.nii.gz) == 1 || $(imtest ../../../T1w/WMLesion/wmlesion.nii.gz) == 1 )) ; then
# 		if (( $(imtest ../../../MNINonLinear/WMLesion/wmlesion.nii.gz) == 1 )) ; then
# 			applywarp -i ../../../MNINonLinear/WMLesion/wmlesion  -r ../../T1w_acpc_dc_restore.nii.gz \
# 			-w ../../../MNINonLinear/xfms/standard2acpc_dc.nii.gz -o wmlesion.nii.gz --interp=nn
# 		elif (( $(imtest ../../../T1w/WMLesion/wmlesion.nii.gz) == 1 )) ; then
# 			fslmaths ../../../T1w/WMLesion/wmlesion wmlesion.nii.gz
# 		fi
# 		fslmaths wmlesion.nii.gz -thr 0 -bin wmlesion_bin.nii.gz # lesion threshold by probability
# 		"$PipelineScripts"/MakeDimto1mm.sh $SPECIES wmlesion_bin.nii.gz nn
# 		mri_convert -ns 1 -odt uchar wmlesion_bin_1mm.nii.gz wmlesion_bin_1mm_conform.nii.gz --conform
# 		fslmaths wmlesion_bin_1mm_conform.nii.gz -mul 110 -max wm.nii.gz wm.nii.gz
# 	fi
# 	## convert back to mgz format 
# 	mri_convert -ns 1 -odt uchar wm.nii.gz wm.mgz  # save in 8-bit
# 	cd $DIR

# }

function generate_wm () {    ####### added by Haiyan, generated wm.mgz and brain.finalsurfs.mgz
	##### Revise begin.
    # edit by yhwei
    # use nBEST to generate white matter mask
    ##### Revise end.
	singularity exec --nv -B "$SubjectDIR"/nBEST:/workspace/demo/data -w ${HCPPIPEDIR}/shared/nbest/nbest python /workspace/demo/nBEST_tissue.py
	mri_convert "$SubjectDIR"/"$SubjectID"/mri/brain.mgz "$SubjectDIR"/"$SubjectID"/mri/brain.nii.gz
	cp "$SubjectDIR"/nBEST/brain_tissue/T1w_DNS_BFC_inm100.nii.gz "$SubjectDIR"/"$SubjectID"/mri/wm_mask.nii.gz
	fslmaths "$SubjectDIR"/"$SubjectID"/mri/brain.nii.gz -mas "$SubjectDIR"/"$SubjectID"/mri/wm_mask.nii.gz "$SubjectDIR"/"$SubjectID"/mri/wm.seg.nii.gz
	mri_convert -ns 1 -odt uchar "$SubjectDIR"/"$SubjectID"/mri/wm.seg.nii.gz "$SubjectDIR"/"$SubjectID"/mri/wm.seg.mgz
	rm "$SubjectDIR"/"$SubjectID"/mri/wm.seg.nii.gz

	###### edit wm with aseg, manually by Haiyan
	###### add
	###### 4: L_Lateral_Ventricle; 43: R_Lateral_Ventricle
	###### 12: L_Putamen; 51: R_Putamen
	###### 10:L_Thalamus_Proper; 49:R_Thalamus_Proper
	###### 11:L_Caudate; 50:R_Caudate
	###### 13:L_Pallidum; 52:R_Pallidum
	###### 26:L_Accumbens-area; 58:R_Accumbens-area
	###### 28:L_VentralDC; 60:R_VentralDC
	

	## Paste claustrum to wm.mgz - Takuya Hayashi, Oct 2017 
	DIR=`pwd`
	cd "$SubjectDIR"/"$SubjectID"/mri

	cp wm.seg.mgz wm.asegedit.mgz
	mri_convert wm.asegedit.mgz wm.asegedit.nii.gz
	mri_convert aseg+claustrum.mgz aseg+claustrum.nii.gz
	fslmaths aseg+claustrum.nii.gz -thr 43 -uthr 43 -bin -mul -39 -add aseg+claustrum.nii.gz -thr 4 -uthr 4 -bin -mul 250 \
		-max wm.asegedit.nii.gz wm.asegedit.nii.gz
	fslmaths aseg+claustrum.nii.gz -thr 51 -uthr 51 -bin -mul -39 -add aseg+claustrum.nii.gz -thr 12 -uthr 12 -bin -mul 250 \
		-max wm.asegedit.nii.gz wm.asegedit.nii.gz
	fslmaths aseg+claustrum.nii.gz -thr 49 -uthr 49 -bin -mul -39 -add aseg+claustrum.nii.gz -thr 10 -uthr 10 -bin -mul 250 \
		-max wm.asegedit.nii.gz wm.asegedit.nii.gz
	fslmaths aseg+claustrum.nii.gz -thr 50 -uthr 50 -bin -mul -39 -add aseg+claustrum.nii.gz -thr 11 -uthr 11 -bin -mul 250 \
		-max wm.asegedit.nii.gz wm.asegedit.nii.gz
	fslmaths aseg+claustrum.nii.gz -thr 52 -uthr 52 -bin -mul -39 -add aseg+claustrum.nii.gz -thr 13 -uthr 13 -bin -mul 250 \
		-max wm.asegedit.nii.gz wm.asegedit.nii.gz
	fslmaths aseg+claustrum.nii.gz -thr 58 -uthr 58 -bin -mul -32 -add aseg+claustrum.nii.gz -thr 26 -uthr 26 -bin -mul 250 \
		-max wm.asegedit.nii.gz wm.asegedit.nii.gz
	fslmaths aseg+claustrum.nii.gz -thr 60 -uthr 60 -bin -mul -32 -add aseg+claustrum.nii.gz -thr 28 -uthr 28 -bin -mul 250 \
		-max wm.asegedit.nii.gz wm.asegedit.nii.gz
	# pasting claustrum to wm.mgz
	fslmaths aseg+claustrum.nii.gz -thr 138 -uthr 138 -bin -add aseg+claustrum.nii.gz -thr 139 -uthr 139 -bin -mul 250 \
		-max wm.asegedit.nii.gz wm.asegedit.nii.gz

	mri_convert -ns 1 -odt uchar wm.asegedit.nii.gz wm.asegedit.mgz 
	mri_pretess "$SubjectDIR"/"$SubjectID"/mri/wm.asegedit.mgz wm "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz "$SubjectDIR"/"$SubjectID"/mri/wm.mgz


    # Added by Haiyan: 
	mri_convert wm.mgz wm.nii.gz
    # pad the hole on between wm and subcortical on wm.nii.gz 
	applywarp -i ${HCPPIPEDIR}/global/templates/wm_MNI_complement.nii.gz  -r ../../T1w_acpc_dc_restore.nii.gz \
			-w ../../../MNINonLinear/xfms/standard2acpc_dc.nii.gz -o wm_complement.nii.gz --interp=nn
	"$PipelineScripts"/MakeDimto1mm.sh $SPECIES "$SubjectDIR"/"$SubjectID"/mri/wm_complement.nii.gz
	mri_convert wm_complement_1mm.nii.gz wm_complement_1mm_LIA.nii.gz --out_orientation LIA -rt nearest
	3dZeropad -RL 256 -AP 256 -IS 256 -prefix  wm_complement_1mm_LIA_256.nii.gz  wm_complement_1mm_LIA.nii.gz 
	fslmaths wm_complement_1mm_LIA_256.nii.gz -bin -mul 250 -max wm.nii.gz wm.nii.gz
	
    # remove a slice to seperate L and R hemis, to generate lh/rh surface seperately
	applywarp -i ${HCPPIPEDIR}/global/templates/wmlesion_LR.nii.gz  -r ../../T1w_acpc_dc_restore.nii.gz \
			-w ../../../MNINonLinear/xfms/standard2acpc_dc.nii.gz -o wmlesion_LR.nii.gz --interp=nn
	"$PipelineScripts"/MakeDimto1mm.sh $SPECIES "$SubjectDIR"/"$SubjectID"/mri/wmlesion_LR.nii.gz
	mri_convert wmlesion_LR_1mm.nii.gz wmlesion_LR_1mm_LIA.nii.gz --out_orientation LIA -rt nearest
	3dZeropad -RL 256 -AP 256 -IS 256 -prefix  wmlesion_LR_1mm_LIA_256.nii.gz  wmlesion_LR_1mm_LIA.nii.gz 
	fslmaths wm.nii.gz -mul wmlesion_LR_1mm_LIA_256.nii.gz wm_temp.nii.gz
	fslmaths wm.nii.gz -sub wm_temp.nii.gz wm.nii.gz

	# remove the cerebellum and brain stem part from wm.nii.gz
	fslmaths wm.nii.gz -mas brain_cerebrum_mask.nii.gz wm.nii.gz
	
	## convert back to mgz format 
	mri_convert -ns 1 -odt uchar wm.nii.gz wm.mgz # save in 8-bit


	# Added by Haiyan: 
	cp brainmask.mgz brain.finalsurfs.mgz
	# set the CSF in brain.finalsurfs.mgz to be zero
	mri_convert brain.finalsurfs.mgz brain.finalsurfs.nii.gz
	fslmaths brain.finalsurfs.nii.gz -mas CSF_mask_erode.nii.gz brain.finalsurfs.CSF.nii.gz
	fslmaths brain.finalsurfs.nii.gz -sub brain.finalsurfs.CSF.nii.gz brain.finalsurfs.nii.gz
	# remove the cerebellum and brain stem part from brain.finalsurfs.nii.gz
	fslmaths brain.finalsurfs.nii.gz -mas brain_cerebrum_mask.nii.gz brain.finalsurfs.nii.gz
	
	## convert back to mgz format 
	mri_convert -ns 1 -odt uchar brain.finalsurfs.nii.gz brain.finalsurfs.mgz
	rm brain.finalsurfs.nii.gz


	# cmd="mri_binarize --i wm.mgz --min 10 --o test.mgz --binval 110";
	# echo $cmd |& tee -a $LF
	# $cmd |& tee -a $LF
	mri_binarize --i wm.mgz --min 10 --o test.mgz --binval 110
	# Haiyan added: 2024/03/21, to further improve the contrast between gm and wm
	# mris_calc -o test2.mgz test.mgz mult 2


	cp  brain.finalsurfs.mgz bkorig.brain.finalsurfs_old.mgz

	#make the white matter in brain.finalsurfs.mgz more brighter than before. 
	# cmd="mris_calc -o new.brain.finalsurfs.mgz brain.finalsurfs.mgz add test.mgz";
	# echo $cmd |& tee -a $LF
	# $cmd |& tee -a $LF
	mris_calc -o new.brain.finalsurfs.mgz brain.finalsurfs.mgz add test.mgz
	

	#Normalize the white-matter in new.brain.finalsurfs.mgz
	cmd="mri_normalize new.brain.finalsurfs.mgz normnew.brain.finalsurfs.mgz"
	echo $cmd |& tee -a $LF
	$cmd |& tee -a $LF
	cp normnew.brain.finalsurfs.mgz brain.finalsurfs.mgz

	# remove a slice to seperate L and R hemis, to generate lh/rh surface seperately
	mri_convert brain.finalsurfs.mgz brain.finalsurfs.nii.gz
	fslmaths brain.finalsurfs.nii.gz -mul wmlesion_LR_1mm_LIA_256.nii.gz brain.finalsurfs_temp.nii.gz
	fslmaths brain.finalsurfs.nii.gz -sub brain.finalsurfs_temp.nii.gz brain.finalsurfs.nii.gz
	mri_convert -ns 1 -odt uchar brain.finalsurfs.nii.gz brain.finalsurfs.mgz
	rm brain.finalsurfs.nii.gz
	cd $DIR
}

function runFSwhite1 () {

        ## Replace claustrum by putamen in aseg for accurate white surface estimation with mris_make_surface - Takuya Hayashi, Oct 2017
        DIR=`pwd`
        cd "$SubjectDIR"/"$SubjectID"/mri
        fslmaths aseg+claustrum.nii.gz -thr 139 -uthr 139 -bin -mul 51 claustrum2putamen.rh
        fslmaths aseg+claustrum.nii.gz -thr 138 -uthr 138 -bin -mul 12 claustrum2putamen.lh
        fslmaths aseg+claustrum.nii.gz -thr 138 -uthr 138 -bin -add aseg+claustrum.nii.gz -thr 139 -uthr 139 -binv \
        -mul aseg+claustrum.nii.gz -add claustrum2putamen.lh.nii.gz -add claustrum2putamen.rh.nii.gz aseg.nii.gz -odt char
        mri_convert -ns 1 -odt uchar aseg.nii.gz aseg.mgz
        cd $DIR

        log_Msg "Fifth recon-all steps for white"
		recon-all -subjid $SubjectID -sd $SubjectDIR -fill -tessellate -smooth1 \
        	-openmp ${num_cores} ${seed_cmd_appendix}

		DIR=`pwd`
		cd "$SubjectDIR"/"$SubjectID"/surf
		# generate a normal lh.inflated.nofix for showing data
		mris_inflate -n 10 -no-save-sulc lh.smoothwm.nofix lh.inflated.nofix
		mris_inflate -n 10 -no-save-sulc rh.smoothwm.nofix rh.inflated.nofix
		mv lh.inflated.nofix lh.inflated.nofix.10
		mv rh.inflated.nofix rh.inflated.nofix.10
		# generate a more inflated one for dealing with fix error
		# the inflate -n doesn't affect -fix(?h.orig) so much, but affect -white(?h.white.preaparc a lot, high -n generate more smooth surface)
		mris_inflate -n 35 -no-save-sulc lh.smoothwm.nofix lh.inflated.nofix
		mris_inflate -n 35 -no-save-sulc rh.smoothwm.nofix rh.inflated.nofix
		cd $DIR


		recon-all -subjid $SubjectID -sd $SubjectDIR -qsphere -fix -white \
        	-openmp ${num_cores} ${seed_cmd_appendix} 

}

function runFSwhite2 () {
	# Highres and white stuffs and fine-tune T2w to T1w Reg
	log_Msg "High resolution white matter and fine tune T2w to T1w registration"
	if [[ ! $SPECIES =~ Human ]] ; then
		# Modified HiresWhite - Takuya Hayashi for bias-correction of T1w, Jan 2017

		#"$PipelineScripts"/FreeSurferHiresWhite_RIKEN.sh "$SubjectID" "$SubjectDIR" "$T1wImageFile"_1mm.nii.gz \
		# Yue ADD
		"$PipelineScripts"/FreeSurferHiresWhiteNHP.sh "$SubjectID" "$SubjectDIR" "$T1wImageFile"_1mm.nii.gz \
		"$T2wImageFile"_1mm.nii.gz $SPECIES 

	else
		"$PipelineScripts"/FreeSurferHiresWhite.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage"
	fi

	# Intermediate Recon-all Steps
	log_Msg "Sixth recon-all steps"
	if [[ ! $SPECIES =~ Human ]] ; then
		CurvStats=""
		AvgCurv=""
	else
		CurvStats="-curvstats"
		AvgCurv="-avgcurv"
	fi
	# recon-all -subjid $SubjectID -sd $SubjectDIR -hires -smooth2 -inflate2 $CurvStats -sphere -openmp ${num_cores} ${seed_cmd_appendix}

	recon-all -subjid $SubjectID -sd $SubjectDIR -smooth2 -openmp ${num_cores} ${seed_cmd_appendix}
	DIR=`pwd`
	cd "$SubjectDIR"/"$SubjectID"/surf

	# generate a normal lh.inflated.nofix for showing data
	mris_inflate -n 10 lh.smoothwm lh.inflated
	mris_inflate -n 10 rh.smoothwm rh.inflated
	mv lh.inflated lh.inflated.10
	mv rh.inflated rh.inflated.10
	# generate a more inflated one for dealing with fix error
	mris_inflate -n 35 lh.smoothwm lh.inflated
	mris_curvature -thresh .999 -n -a 5 -w -distances 10 10 lh.inflated
	mris_inflate -n 35 rh.smoothwm rh.inflated
	mris_curvature -thresh .999 -n -a 5 -w -distances 10 10 rh.inflated
	cd $DIR

	recon-all -subjid $SubjectID -sd $SubjectDIR $CurvStats -sphere -openmp ${num_cores} ${seed_cmd_appendix}
}


function runFSwhite () {

	## Replace claustrum by putamen in aseg for accurate white surface estimation with mris_make_surface - Takuya Hayashi, Oct 2017
	DIR=`pwd`
	cd "$SubjectDIR"/"$SubjectID"/mri
	fslmaths aseg+claustrum.nii.gz -thr 139 -uthr 139 -bin -mul 51 claustrum2putamen.rh
	fslmaths aseg+claustrum.nii.gz -thr 138 -uthr 138 -bin -mul 12 claustrum2putamen.lh
	fslmaths aseg+claustrum.nii.gz -thr 138 -uthr 138 -bin -add aseg+claustrum.nii.gz -thr 139 -uthr 139 -binv \
	-mul aseg+claustrum.nii.gz -add claustrum2putamen.lh.nii.gz -add claustrum2putamen.rh.nii.gz aseg.nii.gz -odt char
	mri_convert -ns 1 -odt uchar aseg.nii.gz aseg.mgz
	cd $DIR

	log_Msg "Fifth recon-all steps for white"
	recon-all -subjid $SubjectID -sd $SubjectDIR -fill -tessellate -smooth1 -inflate1 -qsphere -fix -white \
	-openmp ${num_cores} ${seed_cmd_appendix}

	# Highres and white stuffs and fine-tune T2w to T1w Reg
	log_Msg "High resolution white matter and fine tune T2w to T1w registration"
	if [[ ! $SPECIES =~ Human ]] ; then
		# Modified HiresWhite - Takuya Hayashi for bias-correction of T1w, Jan 2017

		#"$PipelineScripts"/FreeSurferHiresWhite_RIKEN.sh "$SubjectID" "$SubjectDIR" "$T1wImageFile"_1mm.nii.gz \
		# Yue ADD
		"$PipelineScripts"/FreeSurferHiresWhiteNHP.sh "$SubjectID" "$SubjectDIR" "$T1wImageFile"_1mm.nii.gz \
		"$T2wImageFile"_1mm.nii.gz $SPECIES 

	else
		"$PipelineScripts"/FreeSurferHiresWhite.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage"
	fi

	#Intermediate Recon-all Steps
	log_Msg "Sixth recon-all steps"
	if [[ ! $SPECIES =~ Human ]] ; then
		CurvStats=""
		AvgCurv=""
	else
		CurvStats="-curvstats"
		AvgCurv="-avgcurv"
	fi
	recon-all -subjid $SubjectID -sd $SubjectDIR -smooth2 -inflate2 $CurvStats -sphere 

}

function runFSsurfreg () {
	log_Msg "Surface registration"
	# Constrain surface registration in FS in Marmoset- Takuya Hayashi Jan 2018
	if [[ $SPECIES =~ Marmoset ]] ; then
		dist="-dist 20";
		max_degrees="-max_degrees 50";
	else
		dist=""; # Default is 5
		max_degrees="";  # Default is 68
	fi
	DIR=`pwd`
	cd "$SubjectDIR"/"$SubjectID"/surf
	for hemi in lh rh; do
		mris_register -curv $dist $max_degrees ${hemi}.sphere $GCAdir/${hemi}.average.curvature.filled.buckner40.tif ${hemi}.sphere.reg
	done
	cd $DIR

	log_Msg "Seventh recon-all steps"
	if [[ ! $SPECIES =~ Human ]] ; then
		AvgCurv=""
	else
		AvgCurv="-avgcurv"
	fi
	recon-all -subjid $SubjectID -sd $SubjectDIR -jacobian_white $AvgCurv -cortparc

}

function runFSpial () {

	#Highres pial stuff (this module adjusts the pial surface based on the the T2w image)
	log_Msg "High resolution pial surface"
	if [[ ! $SPECIES =~ Human ]] ; then
		# Modified HiresPial - Takuya Hayashi for bias-correction of T2w, Jan 2017
		#"$PipelineScripts"/FreeSurferHiresPial_RIKEN.sh "$SubjectID" "$SubjectDIR" "$T1wImageFile"_1mm.nii.gz \
		"$PipelineScripts"/FreeSurferHiresPialNHP.sh "$SubjectID" "$SubjectDIR" "$T1wImageFile"_1mm.nii.gz \
		"$T2wImageFile"_1mm.nii.gz "$T2wFlag" "$SPECIES"
	else
		"$PipelineScripts"/FreeSurferHiresPial.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage" "$MaxThickness"
	fi

	#Final Recon-all Steps
	log_Msg "Final recon-all steps"
	if [[ ! $SPECIES =~ Human ]] ; then
		cp "$SubjectDIR"/"$SubjectID"/mri/aseg.mgz "$SubjectDIR"/"$SubjectID"/mri/wmparc.mgz
	else
		recon-all -subjid $SubjectID -sd $SubjectDIR -surfvolume -parcstats -cortparc2 -parcstats2 -cortparc3 -parcstats3 -cortribbon \
		-segstats -aparc2aseg -wmparc -balabels -label-exvivo-ec -openmp ${num_cores} ${seed_cmd_appendix}
	fi

}

function runFSfinish () {

if [[ ! $SPECIES =~ Human ]] ; then

	log_Msg "Rescale volume and surface to native space"
	# RescaleVolumeTransform=${HCPPIPEDIR}/global/templates/fs_xfms/${SPECIES}_rescale
	mv "$SubjectDIR"/"$SubjectID" "$SubjectDIR"/"$SubjectID"_1mm
	mkdir -p "$SubjectDIR"/"$SubjectID"/mri
	mkdir -p "$SubjectDIR"/"$SubjectID"/mri/transforms
	mkdir -p "$SubjectDIR"/"$SubjectID"/surf
	mkdir -p "$SubjectDIR"/"$SubjectID"/label
	"$PipelineScripts"/RescaleVolumeAndSurface.sh "$SubjectDIR" "$SubjectID" "$RescaleVolumeTransform" "$T1wImage"

fi

exit 0;

}

function main {

if   [ "$RunMode" = "0" ] ; then 

	runFSinit;runNormalize1;runseg;runFSaseg;runNormalize2;

elif [ "$RunMode" = "1" ] ; then

	runNormalize1;runFSbrainmaskandseg;runFSaseg;runNormalize2;runFSwhite;runFSsurfreg;runFSpial;runFSfinish;

elif [ "$RunMode" = "2" ] ; then

	generate_wm;

elif [ "$RunMode" = "3" ] ; then

	if [ "$AsegEdit" != "NONE" ] ; then
		cp $AsegEdit "$SubjectDIR"/"$SubjectID"/mri/aseg.auto_noCCseg.mgz
	fi
	runFSaseg;runNormalize2;runFSwhite;runFSsurfreg;runFSpial;runFSfinish;
elif [ "$RunMode" = "31" ] ; then

        runFSwhite1;runFSwhite2;runFSsurfreg;

elif [ "$RunMode" = "32" ] ; then

        runFSpial;

elif [ "$RunMode" = "4" ] ; then

	if [ "$ControlPoints" != "NONE" ] ; then
		mkdir -p "$SubjectDIR"/"$SubjectID"/tmp
		cp "$ControlPoints" "$SubjectDIR"/"$SubjectID"/tmp/control.dat
		# the following line is to suppress error in mris_fix_toplogy
		for i in lh.curv rh.curv ; do if [ -e "$SubjectDIR"/"$SubjectID"/surf/$i ] ; then rm "$SubjectDIR"/"$SubjectID"/surf/$i ;fi;done 
	fi
	runNormalize2;runFSwhite;runFSsurfreg;runFSpial;runFSfinish;
	rm -rf "$SubjectDIR"/"$SubjectID"/tmp/control.dat

elif [ "$RunMode" = "5" ] ; then

	if [ "$WmEdit" != "NONE" ] ; then
		WM="wm"
		while [ -e "$SubjectDIR"/"$SubjectID"/mri/${WM}.mgz ] ; do
			WM="${WM}+"
		done
		mv "$SubjectDIR"/"$SubjectID"/mri/wm.mgz "$SubjectDIR"/"$SubjectID"/mri/${WM}.mgz
		cp $WmEdit "$SubjectDIR"/"$SubjectID"/mri/wm.mgz 
	fi
	runFSwhite;runFSsurfreg;runFSpial;runFSfinish;

elif [ "$RunMode" = "6" ] ; then

	runFSsurfreg;runFSpial;runFSfinish;

elif [ "$RunMode" = "7" ] ; then

	runFSpial;runFSfinish;

elif [ "$RunMode" = "8" ] ; then

	runFSfinish;

fi

}

main;
