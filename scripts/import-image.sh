#!/usr/bin/env bash
set -euo pipefail

bucket="${S3_BUCKET:?S3_BUCKET required}"
key="${S3_KEY:?S3_KEY required}"
region="${AWS_REGION:?AWS_REGION required}"

boot_mode="legacy-bios"
arch="${AMI_ARCH:-x86_64}"
format="${IMAGE_FORMAT:-}"
if [ -z "${format}" ]; then
  ext="${key##*.}"
  ext="$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]')"
  case "${ext}" in
    img|raw)
      format="raw"
      ;;
    vhd)
      format="vhd"
      ;;
    vmdk)
      format="vmdk"
      ;;
    *)
      echo "Unable to infer image format from S3 key: ${key}" >&2
      exit 1
      ;;
  esac
fi

timestamp="$(date -u +%Y%m%d%H%M%S)"
ami_name="${AMI_NAME:-clawdinator-nixos-${timestamp}}"
ami_description="${AMI_DESCRIPTION:-clawdinator-nixos}"

task_id="$(
  aws ec2 import-snapshot \
    --region "${region}" \
    --description "${ami_description}" \
    --role-name "vmimport" \
    --disk-container "Format=${format},UserBucket={S3Bucket=${bucket},S3Key=${key}}" \
    --query 'ImportTaskId' \
    --output text
)"

if [ -z "${task_id}" ] || [ "${task_id}" = "None" ]; then
  echo "Failed to start import-image task." >&2
  exit 1
fi

for _ in {1..120}; do
  status="$(aws ec2 describe-import-snapshot-tasks \
    --region "${region}" \
    --import-task-ids "${task_id}" \
    --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' \
    --output text)"

  case "${status}" in
    completed)
      snapshot_id="$(aws ec2 describe-import-snapshot-tasks \
        --region "${region}" \
        --import-task-ids "${task_id}" \
        --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' \
        --output text)"
      if [ -z "${snapshot_id}" ] || [ "${snapshot_id}" = "None" ]; then
        echo "Import completed but SnapshotId is missing." >&2
        exit 1
      fi

      image_id="$(aws ec2 register-image \
        --region "${region}" \
        --name "${ami_name}" \
        --description "${ami_description}" \
        --architecture "${arch}" \
        --boot-mode "${boot_mode}" \
        --virtualization-type hvm \
        --ena-support \
        --root-device-name /dev/xvda \
        --block-device-mappings "DeviceName=/dev/xvda,Ebs={SnapshotId=${snapshot_id},DeleteOnTermination=true}" \
        --query 'ImageId' \
        --output text)"

      if [ -z "${image_id}" ] || [ "${image_id}" = "None" ]; then
        echo "Register-image failed to return ImageId." >&2
        exit 1
      fi

      aws ec2 create-tags \
        --region "${region}" \
        --resources "${image_id}" \
        --tags "Key=Name,Value=${ami_name}" "Key=clawdinator,Value=true"
      echo "AMI_ID=${image_id}" >&2
      echo "${image_id}"
      exit 0
      ;;
    deleted|deleting|error)
      message="$(aws ec2 describe-import-snapshot-tasks \
        --region "${region}" \
        --import-task-ids "${task_id}" \
        --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.StatusMessage' \
        --output text)"
      echo "Import failed: ${status} - ${message}" >&2
      exit 1
      ;;
    *)
      sleep 30
      ;;
  esac
done

echo "Timed out waiting for AMI import to complete (task ${task_id})." >&2
exit 1
