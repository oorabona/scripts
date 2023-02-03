#!/bin/bash
# Install Azure DevOps Agent
# https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops

# Note: this script might be run as root or as a regular user, hence the use of sudo
# alongside the use of the current user as the default admin_username

agent_version=${1:-"$(cat /tmp/agent_version)"}
agent_pat=${2:-"$(cat /tmp/agent_pat)"}
pool_name=${3:-"$(cat /tmp/pool_name)"}
azureorg=${4:-"$(cat /tmp/azureorg)"}
project_name=${5:-"$(cat /tmp/project_name)"}
admin_username=${6:-"$(whoami)"}
workspace=${7:-"_work"}

echo "Installing Azure DevOps Agent '${agent_version}' on $HOSTNAME to join pool '${pool_name}' for project '${project_name}' in Azure Org '${azureorg}'"
echo
echo "/!\ This is an *unattended* installation, so you will not be able to interact with the installation process. /!\\"

# Make sure we have all required parameters
if [ -z "${agent_version}" ] || [ -z "${agent_pat}" ] || [ -z "${pool_name}" ] || [ -z "${azureorg}" ] || [ -z "${project_name}" ]
then
    echo "Missing mandatory parameters, aborting"
    exit 1
fi

# Make sure there is no lock left from previous runs
# FIXME: this is a workaround for a bug in the Azure DevOps Agent
# And actually this is not enough since the APT repository is in an unstable state and packages should also be fixed
sudo rm -rf /var/lib/apt/lists/lock

# Install dependencies
sudo apt-get update
sudo apt dist-upgrade -y
sudo apt-get install -y gnupg software-properties-common curl libunwind8 gettext apt-transport-https unzip zip

# Install and register Azure Pipeline Agent
# Related to inability for the native extension to deploy agent in pools, see for reference
# # https://stackoverflow.com/questions/59861415/installing-self-hosted-agent-remotely-and-wants-to-make-it-active-agent-and-need
# We must install the agent manually ...
# https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops
mkdir azagent
cd azagent
curl -fkSL -o vstsagent.tar.gz https://vstsagentpackage.azureedge.net/agent/${agent_version}/vsts-agent-linux-x64-${agent_version}.tar.gz
tar -zxvf vstsagent.tar.gz

# Make sure the agent is owned by the current (admin) user
# Note that this script might be run as root, so we need to make sure the agent is owned by the current user
chown -R ${admin_username}. .

# Ensure that all folders and files are readable and executable if they already have the eXecute flag
chmod -R +rX /var/lib/waagent

if [ -x "$(command -v systemctl)" ]
then
    (sudo -u ${admin_username} ./config.sh --unattended \
        --pool ${pool_name} --acceptteeeula \
        --agent $HOSTNAME --url https://dev.azure.com/${azureorg}/ \
        --work ${workspace} --projectname ${project_name} \
        --auth PAT --token ${agent_pat} --runasservice)
    sudo ./svc.sh install
    sudo ./svc.sh start
else
    (sudo -u ${admin_username} ./config.sh --unattended \
        --pool ${pool_name} --acceptteeeula \
        --agent $HOSTNAME --url https://dev.azure.com/${azureorg}/ \
        --work ${workspace} --projectname ${project_name} \
        --auth PAT --token ${agent_pat})
    (sudo -u ${admin_username} ./run.sh)
fi

# TODO define version
# See https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
