#!/bin/sh
python_version=${1:-"$(cat /tmp/python_version)"}
python_cmd=${2:-"python${python_version}"}
toolset_path=${3:-"$(pwd)/_work/_tool"}

# Make sure we have all required parameters
if [ -z "${python_version}" ]
then
    echo "Missing mandatory parameters, aborting"
    exit 1
fi

# Check if toolset path exists
if [ ! -d "${toolset_path}" ]
then
    echo "Toolset path ${toolset_path} does not exist, aborting"
    exit 1
fi

# Install Python the-right-way
# https://dev.to/akaszynski/create-an-azure-self-hosted-agent-without-going-insane-173g
sudo apt-get update && sudo apt-get install -y ${python_cmd} ${python_cmd}-venv
PYTHON_VERSION=$(${python_cmd} -c "import sys; print('.'.join([f'{val}' for val in sys.version_info[:3]]))")
echo "Symlinking Python ${python_version} to $PYTHON_VERSION (ToolSet path: ${toolset_path} )"

mkdir -p ${toolset_path}/Python/${PYTHON_VERSION}/x64
cd ${toolset_path}/Python/
ln -s ${PYTHON_VERSION} ${python_version} && cd ${python_version} && ln -s x64 x86

# Install virtual Python environment
${python_cmd} -m venv x64

# Tell the agent that we have installed Python
touch x64.complete
touch x86.complete
