#!/bin/bash

# how to write it out: ./masking_out_eeg.sh -n racsleep08
# nina fultz may 2021

#gets displayed when -h or --help is put in
display_usage(){
    echo "***************************************************************************************
Script to take bias corrected, eroded, skull mask and apply it to MEMPRAGE to remove eeg artifact 
*************************************************************************************** "
    echo Usage: ./masking_out_eeg.sh -n -d -b
       -n: Name of subject
}

if [ $# -le 1 ]
then
    display_usage
    exit 1
fi

while getopts "n:d" opts;
do
    case $opts in
        n) SUBJECT=$OPTARG ;;
    esac
done

export DIR=/ad/eng/research/eng_research_lewislab/users/nfultz/pet_eeg_fmri/
export EEG_REMOVAL=$DIR/$SUBJECT/eeg_removal
module load fsl
module load freesurfer


#manually threshold and check bone
#save out thresholded file as: $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_bone_thresholded.nii.gz.  - threshold bone! go to tools>threshold>the gui #low: 0.06, high:70, press run, then look at bone image
#save out thresholded file as: $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_other_thresholded.nii.gz - erode them: tools>volume filter> erode
#adding all of WM, GM, CSF, bone, other together

fslmaths $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_CSF.nii.gz -add $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_GM.nii.gz -add $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_WM.nii.gz -add $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_bone_thresholded.nii.gz -add $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_other_thresholded.nii.gz $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_other_WM_CSF_GM_bone.nii.gz


FILE=$DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_other_WM_CSF_GM_bone.nii.gz   
if [ -f $FILE ]; then
   echo "File ${FILE##*/} exists. part 1 is all done! go manually check this!"
else
   echo "File ${FILE##*/} does not exist. Something went wrong with adding the CSF, GM, bone, other, and WM together! "
fi


#masking out MEMPRAGE with this MEMPR_iso1mm_other_eroded_and_WM_CSF_GM_bone.nii.gz file: 
    #-mas   : use (following image>0) to mask current image

fslmaths $DIR/$SUBJECT/anat/MEMPR_iso1mm.nii.gz -mas $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_other_WM_CSF_GM_bone.nii.gz $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_noeeg.nii.gz

#fslmask($DIR/$SUBJECT/anat/MEMPR_iso1mm.nii.gz, $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_other_eroded_and_WM_CSF_GM_bone.nii.gz, $DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_FINAL_noeeg.nii.gz)

FILE=$DIR/$SUBJECT/eeg_removal/MEMPR_iso1mm_noeeg.nii.gz   
if [ -f $FILE ]; then
   echo "File ${FILE##*/} exists. part 2 (eeg removal from MEMPRAGE) is all done! go manually check this!"
else
   echo "File ${FILE##*/} does not exist. Something went wrong with subtracting the mask from the MEMPRAGE! "
fi
