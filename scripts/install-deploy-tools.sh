#!/bin/bash
set -e
self="${0#./}"
base="${self%/*}"
current=`pwd`
if [ "$base" = "$self" ] ; then
    readonly script_dir=$current
elif [[ $base =~ ^/ ]]; then
    readonly script_dir="$base"
else
    readonly script_dir="$current/$base"
fi


export PATH

readonly BIN_PATH="$(pwd)/bin"
readonly TERRAFORM_VERSION='0.11.13'

PATH="${BIN_PATH}:${PATH}"

if [[ ! -f "${BIN_PATH}/terraform" ]]; then
  case "$OSTYPE" in
    darwin*)  wget -O /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_darwin_amd64.zip" ;;
    linux*)   wget -O /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" ;;
  esac
  unzip -d "${PWD}/bin" /tmp/terraform.zip
  terraform -v
fi
