#!/bin/sh
python_version=${1:-"$(cat /tmp/python_version)"}
python_cmd=${2:-"python${python_version}"}

# Make sure we have all required parameters
if [ -z "${python_version}" ] || [ -z "${python_cmd}" ]
then
    echo "Missing mandatory parameters, aborting"
    exit 1
fi

# Install Python the-right-way
# https://dev.to/akaszynski/create-an-azure-self-hosted-agent-without-going-insane-173g
sudo apt-get update && sudo apt-get install -y ${python_cmd} ${python_cmd}-venv
PYTHON_VERSION=$(${python_cmd} -c "import sys; print('.'.join([f'{val}' for val in sys.version_info[:3]]))")
echo "Symlinking Python ${python_version} to $PYTHON_VERSION (work path: )"

