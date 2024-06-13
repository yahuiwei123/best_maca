#!/bin/bash
set -e
# edit by yhwei
##### 实现了输入一个被试对应的主文件夹，以及其下要处理的dicom文件夹，输出对应所有转换为Nifty的结果
# e.g. sh dcm2nii.sh dataset/SK1002_22039 [T1_MP2RAGE_SAG_P3_ISO_4AVG_INV1_0003] dataset/SK1002_22039/RawData/

SUBJECT_DIR="$1"
SESS_LIST="$2"
OUTPUT_DIR="$3"

# 解析列表参数
parsed_list=$(echo "$SESS_LIST" | sed 's/\[\(.*\)\]/\1/' | tr ',' '\n')
mkdir -p ${OUTPUT_DIR}
for sess in $parsed_list; do
    # convert Dicom to Nifty
    DICOM_PATH=${SUBJECT_DIR}/${sess}
    dcm2niix -z -o $OUTPUT_DIR -f ${sess} $DICOM_PATH
    echo "Dicom convert to Nifti finished."
done