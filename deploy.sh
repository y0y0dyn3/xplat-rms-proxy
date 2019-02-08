#! /bin/bash

STAGE=$1
SERVICE_NAME=$2
SERVICE_DIR=$3
S3_REGION=${4:-"us-east-1"}

export PATH
PATH=$(pwd)/bin:$PATH

if [ -z "${STAGE}" ]; then
  echo "Usage: ./deploy.sh <stage> <service_name> <service_directory> [s3_region]"
  exit 1
fi

# Use dev.tfvars in dev, prod.tfvars in prod
[[ $STAGE = "prod" ]] && VARSFILESTAGE="prod" || VARSFILESTAGE="dev"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query "Account")
BUCKET="${AWS_ACCOUNT_ID}-terraform"


if ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1
then
  echo "Terraform state file S3 bucket ${BUCKET} does not exist."
  echo "Creating s3://${BUCKET} in ${S3_REGION}..."

  if ! aws s3 mb s3://"$BUCKET" --region "$S3_REGION"
  then
    echo "Error creating s3://${BUCKET}. Exiting."
    exit 1
  fi

  echo "Enabling versioning for s3://${BUCKET}"
  aws s3api put-bucket-versioning --bucket ${BUCKET} --versioning-configuration Status=Enabled
else
  echo "Terraform state file S3 bucket ${BUCKET} exists."
fi

run_terraform() {
  set -e
  set -x
  terraform init -backend=true \
    -backend-config="bucket=${BUCKET}" \
    -backend-config="region=${S3_REGION}" \
    -backend-config="key=${SERVICE_NAME}/${STAGE}/terraform.tfstate"
  terraform plan -var "stage=${STAGE}" -var-file=${VARSFILESTAGE}.tfvars\
    -out=terraform.plan
 terraform apply -auto-approve terraform.plan
}

pushd "${SERVICE_DIR}"
  run_terraform
popd
