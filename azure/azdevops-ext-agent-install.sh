#!/bin/bash
# Install Azure DevOps Agent
# https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops

# Some elements of this script are inspired from the following sources:
# - https://vstsagenttools.blob.core.windows.net/tools/ElasticPools/Linux/14/enableagent.sh
export LOGFILE="/var/log/azdevops-ext-agent-install.log"

log_message()
{
    message=$1
    timestamp="$(date -u +'%F %T')"
    echo "$timestamp" "$message"
    echo "$timestamp" "$message" >> "$LOGFILE"
}

decode_string() 
{
    echo "$1" | sed 's/+/ /g; s/%/\\x/g;' | xargs -0 printf '%b' # substitute + with space and % with \x
}

log_message "Azure DevOps Agent Installation Script"

# Note: this script might be run as root or as a regular user, hence the use of sudo
# alongside the use of the current user as the default admin_username

agent_version=${1:-"$(cat /tmp/agent_version)"}
agent_pat=${2:-"$(cat /tmp/agent_pat)"}
pool_name=${3:-"$(cat /tmp/pool_name)"}
azureorg=${4:-"$(cat /tmp/azureorg)"}
project_name=${5:-"$(cat /tmp/project_name)"}
installation_path=${6:-"/agent"}
admin_username=${7:-"AzDevOps"}
workspace=${8:-"_work"}

log_message "Installing Azure DevOps Agent '${agent_version}' on $HOSTNAME under the ${installation_path} directory."
log_message "Agent will join pool '${pool_name}' for project '${project_name}' in Azure Org '${azureorg}'"
log_message "/!\ This is an *unattended* installation, so you will not be able to interact with the installation process. /!\\"

# Make sure we have all required parameters
if [ -z "${agent_version}" ] || [ -z "${agent_pat}" ] || [ -z "${pool_name}" ] || [ -z "${azureorg}" ] || [ -z "${project_name}" ]
then
    echo "Missing mandatory parameters, aborting"
    exit 1
fi

# Make sure there is no lock left from previous runs
# FIXME: this is a workaround for a bug in the Azure DevOps Agent
# And actually this is not enough since the APT repository would be in an unstable state and packages should also be fixed
sudo rm -rf /var/lib/apt/lists/lock

# Install dependencies
sudo apt-get update
sudo apt dist-upgrade -y
sudo apt-get install -y gnupg software-properties-common curl libunwind8 gettext apt-transport-https unzip zip

# Check if the agent was previously configured.  If so then abort
if (test -f "$installation_path/.agent"); then
    log_message "Agent was already configured. Doing nothing."
    exit
fi

# Create our user account if it does not exist already
if id $admin_username &>/dev/null; then
    log_message "$admin_username account already exists"
else
    log_message "Creating $admin_username account"
    sudo useradd -m $admin_username
    sudo usermod -a -G docker $admin_username
    sudo usermod -a -G adm $admin_username
    sudo usermod -a -G sudo $admin_username

    log_message "Giving $admin_username user access to the '/home' directory"
    sudo chmod -R +r /home
    setfacl -Rdm "u:$admin_username:rwX" /home
    setfacl -Rb /home/$admin_username
    echo "$admin_username ALL=NOPASSWD: ALL" >> /etc/sudoers
fi

# Install and register Azure Pipeline Agent
# Related to inability for the native extension to deploy agent in pools, see for reference
# # https://stackoverflow.com/questions/59861415/installing-self-hosted-agent-remotely-and-wants-to-make-it-active-agent-and-need
# We must install the agent manually ...
# https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops
mkdir -p ${installation_path}
cd ${installation_path}
curl -fkSL -o vstsagent.tar.gz https://vstsagentpackage.azureedge.net/agent/${agent_version}/vsts-agent-linux-x64-${agent_version}.tar.gz
tar -zxvf vstsagent.tar.gz

# Make sure the agent is owned by the current (admin) user
# Note that this script might be run as root, so we need to make sure the agent is owned by the current user
chown -R ${admin_username}. .

# Ensure that all folders and files are readable and executable if they already have the eXecute flag
chmod -R +rX $(realpath ${installation_path}|cut -d'/' -f1-3)

# install dependencies
log_message "Installing dependencies"

set -o pipefail
bash -x ./bin/installdependencies.sh 2>&1 > /dev/null | tee -a "$LOGFILE"
retValue=$?
set +o pipefail

if [ $retValue -ne 0 ]; then
    log_message "Dependencies installation failed"
else
    log_message "Dependencies installation succeeded"
fi


# configure the build agent
# calling bash here so the quotation marks around $pool get respected
log_message "Configuring build agent"

# extract proxy configuration if present
extra=''
proxy_url_variable=''
if [ ! -z "$http_proxy"  ]; then
    proxy_url_variable="$http_proxy"
elif [ ! -z "$https_proxy"  ]; then
    proxy_url_variable="$https_proxy"
fi

if [ ! -z "$proxy_url_variable"  ]; then
    log_message "Found a proxy configuration"
    # http://<username>:<password>@<proxy_url/_proxyip>:<port>
    proxy_username=''
    proxy_password=''
    proxy_url=''
    if [[ "$proxy_url_variable" != *"@"* ]]; then
        # no username and passowrd
        proxy_url="$proxy_url_variable"
        extra="--proxyurl $proxy_url_variable"
        log_message "Found proxy url $proxy_url"
    else
        # we need to also extract username and password and decode them (the agent will try to encode them again)
        proxy_url=$(echo "$proxy_url_variable" | cut -d'/' -f 1 )"//"$(echo "$proxy_url_variable" | cut -d'@' -f 2 )
        proxy_username=$(echo "$proxy_url_variable" | cut -d':' -f 2 | cut -d'/' -f 3)
        proxy_password=$(echo "$proxy_url_variable" | cut -d'@' -f 1 | cut -d':' -f 3)
        proxy_username=$(decode_string "$proxy_username")
        proxy_password=$(decode_string "$proxy_password")
        extra="--proxyurl $proxy_url --proxyusername $proxy_username --proxypassword $proxy_password"
        log_message "Found proxy url $proxy_url and authentication info"
    fi
fi

log_message "Configuring agent"

if [ -x "$(command -v systemctl)" ]
then
    OUTPUT=$(sudo -E runuser ${admin_username} -c "/bin/bash config.sh --unattended \
        --pool \"${pool_name}\" --acceptteeeula \
        --agent $HOSTNAME --url https://dev.azure.com/${azureorg}/ \
        --work ${workspace} --projectname ${project_name} \
        --replace --runasservice --auth PAT --token ${agent_pat} \
        $extra" 2>&1)
    retValue=$?
    log_message "$OUTPUT"
    if [ $retValue -ne 0 ]; then
        log_message "Build agent configuration failed"
        exit 100
    fi

    sudo ./svc.sh install
    sudo ./svc.sh start
else
    OUTPUT=$(sudo -E runuser ${admin_username} -c "/bin/bash config.sh --unattended \
        --pool \"${pool_name}\" --acceptteeeula \
        --agent $HOSTNAME --url https://dev.azure.com/${azureorg}/ \
        --work ${workspace} --projectname ${project_name} \
        --replace --auth PAT --token ${agent_pat} \
        $extra" 2>&1)
    retValue=$?
    log_message "$OUTPUT"
    if [ $retValue -ne 0 ]; then
        log_message "Build agent configuration failed"
        exit 100
    fi

    # run agent in the background and detach it from the terminal
    log_message "Starting agent"
    sudo -E nice -n 0 runuser $admin_username -c "/bin/bash ${installation_path}/run.sh" > /dev/null 2>&1 &

    log_message "Going to run disown"
    disown
fi
