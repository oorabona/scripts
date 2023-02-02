#!/bin/sh

# Install Terraform
# https://learn.hashicorp.com/tutorials/terraform/install-cli

terraform_version=${1:-"$(cat /tmp/terraform_version)"}

# Make sure we have all required parameters
if [ -z "${terraform_version}" ]
then
    echo "Missing mandatory parameters, aborting"
    exit 1
fi

# Avoid having to create a script and host it 'somewhere'
# See https://learn.hashicorp.com/tutorials/terraform/install-cli
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository -y \"deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main\"
sudo apt-get update && sudo apt-get install -y terraform=${terraform_version}

# TODO define version
sudo apt-get install -y 
curl https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

