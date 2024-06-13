#!/bin/bash
set -e
set -x
###### This script is used to prepare for the T1w and T2w for conducting surface generation(NHPHCPPipeline).
###### You'd better run by each step. Because you should select which runs to use and check the intermediate results.
###### You'd better run it on L0109, because docker are needed.

# Help message
usage () {
echo "
=== preprocess ===

This script provides some basic alternative procedure for sMRI:
1) dcm to nii
2) correct the direction
3) average different runs
4) obtain brain mask through nBEST (a deeplearning based tool)
5) if no T2 generate a fake one

Usage:
sh T1step_prepare_Hyde.sh -i [movable] -o [output directory] -g [gca file path] -r [registration stages] [-c]

Required arguments:
-i	input volume (to be registered to Talairach space, needs to be skullstripped).
-o	output directory (e.g. ${subject}/mri/transforms).
-g	gca file path

Optional arguments
-r	number of Talairach registration steps.
	1: source > Talairach, 
	2: source > chimpanzee > Talairach 
	3: source > macaque > chimpanzee > Talairach. 
	Default = 1.
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
while getopts ":d:n:k:s:m:ech" opt; do
  case $opt in
    d) RAW_PATH=${OPTARG};;
    n) SUB_PATH=${OPTARG};;
    k) sessions=${OPTARG};;
    s) stages=${OPTARG};;
    m) MODEL_PATH=${OPTARG};;
    e) execute_strip=1;;
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
elif [ "x" == "x$RAW_PATH" ]; then
  echo "-d [dicom path] input is required"
  exit 1
elif [ "x" == "x$SUB_PATH" ]; then
  echo "-n [nifty path] is required"
  exit 1
elif [ "x" == "x$stages" ]; then
  echo "-k [sessions] is required"
  exit 1
elif [ "x" == "x$sessions" ]; then
  echo "-s [stages] is required"
  exit 1
elif [ "x" == "x$MODEL_PATH" ]; then
  echo "-s [segmentation model path] is required"
  exit 1
fi

echo "
Running PreprocessNHP with the following parameters:
- dicom directory: 					${RAW_PATH}
- nifty directory: 				    ${SUB_PATH}
- stages:					        ${stages}
- session list of current subject:	${sessions}
- segmentation model path:          ${MODEL_PATH}"

if [[ clean_up -eq 1 ]]
then
	echo "- clean-up:				yes"
else
	echo "- clean-up:				no"
fi

if [[ execute_strip -eq 1 ]]
then
	echo "- execute_strip:			yes"
else
	echo "- execute_strip:			no"
fi


function FormatUnify () {
    ###### [step1] dcm2niix: convert dicom convert to nifti
    sh ${HCPPIPEDIR}/PreProcess/scripts/Dcm2Nii.sh $RAW_PATH $sessions $PRE_PATH
}

function SavePath() {
    ###### [step2] Save the path of all the T1w or T2w runs in txt files
    if [ "$stages" = "2" ] ; then
        echo ${RAW_PATH}
        cp -r ${RAW_PATH}/* ${PRE_PATH}
    fi

    for Txw in T1w T2w; do    # T1w or T2w
        # Find files
        fn_txt=${PRE_PATH}/${Txw}_files_raw.txt
        > "$fn_txt"
        
        find "$PRE_PATH" -type f -name "*${Txw}*.nii.gz" >> "$fn_txt"
        cp $fn_txt ${PRE_PATH}/${Txw}_files_used.txt
    done
}


######  [step3] Manually remove some runs by removing the correpsonding lines in ${Txw}_files_used.txt using vscode:
######  The 1st run of T1w and T2w are often removed. And also the runs with bad quality.
# For T1w: 3 is the 1st run;
# For T2w: 10 is the 1st run


function AvgPadImage() {
    ###### [step4] Average all the selected runs in T1w or T2w; Padding to 256*256*256
    for Txw in T1w T2w; do    # T1w or T2w
        # Concatenate all the left runs
        files=$(cat "${PRE_PATH}/${Txw}_files_used.txt")
        if [ -z "$files" ]; then
            continue
        fi

        # Average all
        fslmerge -t ${PRE_PATH}/${Txw}_merged.nii.gz $files
        fslmaths ${PRE_PATH}/${Txw}_merged.nii.gz -Tmean ${PRE_PATH}/${Txw}_merged.nii.gz
        # # Then correct the orientations of raw image (Only change header file);
        # mri_convert ${PRE_PATH}/${Txw}_merged.nii.gz ${PRE_PATH}/${Txw}_merged_RIA.nii.gz --in_orientation RIA

        # # As needed by NHPHCPpipeline, zero pad to 256
        # 3dZeropad -RL 256 -AP 256 -IS 256 -prefix ${PRE_PATH}/${Txw}_merged_RIA_256.nii.gz ${PRE_PATH}/${Txw}_merged_RIA.nii.gz

        # # Ad needed by NHPHCPpipeline, change the orientations as LIA (Both in image and header file).
        # mri_convert ${PRE_PATH}/${Txw}_merged_RIA_256.nii.gz ${PRE_PATH}/${Txw}_merged_LIA_256.nii.gz --out_orientation LIA -rt cubic
        cp ${PRE_PATH}/${Txw}_merged.nii.gz ${PRE_PATH}/${Txw}.nii.gz

        # Remove intermediate results
        rm ${PRE_PATH}/${Txw}_merged*.nii.gz
    done
}


function Augment() {
    ##### [step5] Use nBEST to remove skull and get white matter mask: run on L0109, because docker are needed
    ##### nBEST introdution:  https://github.com/TaoZhong11/nBEST
    # Prepare for nBEST
    cp ${PRE_PATH}/T1w.nii.gz ${nBEST_PATH}/T1w.nii.gz
    # Denoise
    DenoiseImage -d 3 -i ${nBEST_PATH}/T1w.nii.gz -n Gaussian -v 1 -o ${nBEST_PATH}/T1w_DNS.nii.gz
    # Biase Field Correction
    N4BiasFieldCorrection -d 3 -i ${nBEST_PATH}/T1w_DNS.nii.gz -b [256, 3] -s 3 -c [100x50x25x10,1e-5] -r 1 -t [0.15,0.01,200] -v 1 -o ${nBEST_PATH}/T1w_DNS_BFC.nii.gz
    # Same mean intensity
    fslmaths ${nBEST_PATH}/T1w_DNS_BFC.nii.gz -mas ${nBEST_PATH}/T1w_DNS_BFC.nii.gz -inm 100 ${nBEST_PATH}/T1w_DNS_BFC_inm100.nii.gz
    # rm intermediate results
    rm ${nBEST_PATH}/T1w.nii.gz
    rm ${nBEST_PATH}/T1w_DNS.nii.gz
    rm ${nBEST_PATH}/T1w_DNS_BFC.nii.gz
}



function SkullStrip() {
    # use nBEST to obtain brain mask
    singularity exec --nv -B ${nBEST_PATH}:/workspace/demo/data -w ${MODEL_PATH} python /workspace/demo/nBEST_brain.py

    ###### [step6] Apply the finalmask to the T1w and T2w; and prepare the data for HCPNHPPipeline
    ## Check the performance of brain mask and wm mask, and if necessary, manually edit them.
    # Check the brain_mask.nii.gz
    # freeview ${nBEST_PATH}/T1w_DNS_BFC_inm100_brain.nii.gz

    cp ${nBEST_PATH}/brain_img/T1w_DNS_BFC_inm100.nii.gz ${PRE_PATH}/T1w.nii.gz
    cp ${nBEST_PATH}/brain_mask/T1w_DNS_BFC_inm100.nii.gz ${PRE_PATH}/brainmask.nii.gz

    ##### If there are no true T2, generate a fake T2.#######
    ###### Apply the finalmask to the T1w
    if [ -f ${PRE_PATH}/T2w.nii.gz ]; then
        fslmaths ${PRE_PATH}/T2w.nii.gz -mas ${PRE_PATH}/brainmask.nii.gz  ${PRE_PATH}/T2w.nii.gz
    else
        MaxValue=`fslstats ${PRE_PATH}/T1w.nii.gz -R | awk '{print $2}'`
        fslmaths ${PRE_PATH}/T1w.nii.gz -sub $MaxValue -mul -1 ${PRE_PATH}/T2w.nii.gz
        fslmaths ${PRE_PATH}/T2w.nii.gz -mas ${PRE_PATH}/brainmask.nii.gz  ${PRE_PATH}/T2w.nii.gz
    fi
}

function Reorient() {
    ###### [step7] Change the image orientation
    
    ##### Undo
    # Register raw image to tamplate, so that the raw image can reorient into right orientation.
    ##### End

    ##### Revise begin.
    # edit by yhwei
    # zero pad T1w and T2w to 256 (FreeSurfer need)
    ##### Revise end.
    for Txw in T1w T2w brainmask; do    # T1w or T2w
        # Concatenate all the left runs
        file=${PRE_PATH}/${Txw}.nii.gz
        if [ -z "$file" ]; then
            continue
        fi
        3dZeropad -RL 256 -AP 256 -IS 256 -prefix ${PRE_PATH}/${Txw}_256.nii.gz $file
        mv ${PRE_PATH}/${Txw}_256.nii.gz $file
    done
}


function main {
    # prepare some varibles
    PRE_PATH=${SUB_PATH}/preprocess
    nBEST_PATH=${SUB_PATH}/nBEST

    # create some necessary directory
    mkdir -p $SUB_PATH
    mkdir -p $nBEST_PATH
    mkdir -p $PRE_PATH


    if   [ "$stages" = "1" ] ; then
        FormatUnify;SavePath;AvgPadImage;
    elif [ "$stages" = "2" ] ; then
        SavePath;AvgPadImage;
    elif [ "$stages" = "3" ] ; then
        AvgPadImage;
    elif [ "$stages" = "4" ] ; then
        echo "If use this mode, make sure -e flag is not activated"
    fi

    # Execute skull strip
    if [[ execute_strip -eq 1 ]]
    then
        Augment;SkullStrip;
    else
        Augment;
        mkdir -p ${nBEST_PATH}/brain_mask
        mkdir -p ${nBEST_PATH}/brain_img
        fslmaths ${PRE_PATH}/T1w.nii.gz -bin ${nBEST_PATH}/brain_mask/T1w_DNS_BFC_inm100.nii.gz
        cp ${PRE_PATH}/T1w.nii.gz ${nBEST_PATH}/brain_img/T1w_DNS_BFC_inm100.nii.gz
    fi

    Reorient;

    # Clean up the files produce in process
    if [[ clean_up -eq 1 ]]
    then
        rm ${PRE_PATH}/*.json
        rm ${PRE_PATH}/*.txt
    fi
}

main;