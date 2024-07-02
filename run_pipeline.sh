#!/bin/bash
set -e


path_script=/n01dat01/yhwei/projects/Monkey_Surface/best_maca
StudyFolder=/n01dat01/yhwei/projects/Monkey_Surface/datasets/test/
Subject=M03

# sh PreProcessPipelineBatchNHP.sh /n01dat01/yhwei/projects/Monkey_Surface/datasets/test/ M03 2 No

# sh ${path_script}/PreFreeSurferPipelineBatchNHP.sh /n01dat01/yhwei/projects/Monkey_Surface/datasets/test/ M03 Yes

# sh ${path_script}/FreeSurferPipelineBatchNHP.sh $StudyFolder $Subject 0

##### [step4]: generate wm.mgz and brain.finalsurf.mgz
sh ${path_script}/FreeSurferPipelineBatchNHP.sh $StudyFolder $Subject 2
    # check wm.mgz and brain.finalsurf.mgz
    #     freeview $StudyFolder/$Subject/T1w/$Subject/mri/brain.mgz \
    #     $StudyFolder/$Subject/T1w/$Subject/mri/wm.mgz  \
    #     $StudyFolder/$Subject/T1w/$Subject/mri/brain.finalsurf.mgz  \
    #     $StudyFolder/$Subject/T1w/$Subject/mri/CSF_mask_erode.nii.gz



# ##### [step5]: generate surfaces
sh ${path_script}/FreeSurferPipelineBatchNHP.sh $StudyFolder $Subject 31

sh ${path_script}/FreeSurferPipelineBatchNHP.sh $StudyFolder $Subject 32
sh ${path_script}/FreeSurferPipelineBatchNHP.sh $StudyFolder $Subject 8