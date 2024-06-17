#!/bin/bash
# edit by yhwei
#Subjlist="M126 M128 M129 M131 M132" #Space delimited list of subject IDs
#StudyFolder="/media/myelin/brainmappers/Connectome_Project/InVivoMacaques" #Location of Subject folders (named by subjectID)
#EnvironmentScript="/media/2TBB/Connectome_Project/Pipelines/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script
EnvironmentScript="/n01dat01/yhwei/projects/Monkey_Surface/best_maca/SetUpHCPPipelineNHP.sh"

# Requirements for this script
#  installed versions of: FSL5.0.2 or higher , FreeSurfer (version 5.2 or higher) , gradunwarp (python code from MGH)
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR , PATH (for gradient_unwarp.py)

#Set up pipeline environment variables and software
. ${EnvironmentScript}
StudyFolder=$1
Subjlist=$2
Stage=$3
withDCM=$4
# Log the originating call
echo "$@"

#if [ X$SGE_ROOT != X ] ; then
    QUEUE="-q long.q"
#fi

PRINTCOM=""
#PRINTCOM="echo"
#QUEUE="-q veryshort.q"

########################################## INPUTS ##########################################

#Scripts called by this script do NOT assume anything about the form of the input names or paths.
#This batch script assumes the HCP raw data naming convention, e.g.

#	${StudyFolder}/${Subject}/unprocessed/3T/T1w_MPR1/${Subject}_3T_T1w_MPR1.nii.gz
#	${StudyFolder}/${Subject}/unprocessed/3T/T1w_MPR2/${Subject}_3T_T1w_MPR2.nii.gz

#	${StudyFolder}/${Subject}/unprocessed/3T/T2w_SPC1/${Subject}_3T_T2w_SPC1.nii.gz
#	${StudyFolder}/${Subject}/unprocessed/3T/T2w_SPC2/${Subject}_3T_T2w_SPC2.nii.gz

#	${StudyFolder}/${Subject}/unprocessed/3T/T1w_MPR1/${Subject}_3T_FieldMap_Magnitude.nii.gz
#	${StudyFolder}/${Subject}/unprocessed/3T/T1w_MPR1/${Subject}_3T_FieldMap_Phase.nii.gz

#Change Scan Settings: FieldMap Delta TE, Sample Spacings, and $UnwarpDir to match your images
#These are set to match the HCP Protocol by default

#If using gradient distortion correction, use the coefficents from your scanner
#The HCP gradient distortion coefficents are only available through Siemens
#Gradient distortion in standard scanners like the Trio is much less than for the HCP Skyra.


######################################### DO WORK ##########################################

for Subject in $Subjlist ; do
  echo $Subject
  . ${EnvironmentScript}
  #Input Images
  DCMInputImages=${StudyFolder}/${Subject}/RawData
  SubjectPath=${StudyFolder}/${Subject}

  #Name list of sessions
  if [ "${withT2}" = "Yes" ] ; then
    SessionImages=`ls -d ${DCMInputImages}/*/ | xargs -I {} basename {} | tr '\n' ',' | sed 's/,$/\n/' | sed 's/^/[/' | sed 's/$/]/'`
  else
    SessionImages=[]
  fi

#  ${FSLDIR}/bin/fsl_sub ${QUEUE} \
     ${HCPPIPEDIR}PreProcess/PreProcessNHP.sh \
      -d ${DCMInputImages} \
      -n ${SubjectPath} \
      -k ${SessionImages} \
      -s ${Stage} \
      -m ${HCPPIPEDIR}/shared/nbest/nbest \
      -e \
      -c \

  # The following lines are used for interactive debugging to set the positional parameters: $1 $2 $3 ...

  echo "set -- --path=${StudyFolder} \
      --subject=${Subject} \
      --dicom=${SessionImages} \
      --stage=${Stage} \
      "

  echo ". ${EnvironmentScript}"

done