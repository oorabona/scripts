#!/bin/bash
# This script will build the WSL2 kernel from the Microsoft repository
# It will also enable you to select the patches to apply to the kernel

# This script assumes you are running a Debian compatible (APT) distribution.
# Check if that it is the case by running the following command:

# DOCKER_MODE=1 means that Docker will be used to build the kernel
# DOCKER_MODE=0 means that the kernel *CANNOT* be built from within Docker and will therefore be built on the host system

SCRIPT_DIR=$(dirname $0)

APT_VERSION=$(apt --version 2>/dev/null | grep -Po '(?<=apt )([0-9]+\.[0-9]+)')
if [[ -z $APT_VERSION ]]; then
    echo "You are not running a Debian compatible distribution."
    echo "Please install the following packages manually:"
    echo "build-essential dwarves libncurses5-dev libssl-dev bison flex libelf-dev rsync"
    echo ""
    echo "-OR-"
    echo ""
    echo "Let this script continue with Docker installation mode enabled."
    echo "This will build the kernel in a Docker container."
    echo ""
    read -p "Press any key to continue or Ctrl+C to exit..."
    DOCKER_MODE=1
fi

# Check that Docker is installed
DOCKER_VERSION=$(docker --version 2>/dev/null | grep -Po '(?<=Docker version )([0-9]+\.[0-9]+\.[0-9]+)')

# By default kernel base path is set to the current directory if unset
KERNEL_BASE_PATH=${KERNEL_BASE_PATH:-$(pwd)}
mkdir -p $KERNEL_BASE_PATH 2>/dev/null

# If Docker is required and not installed then exit
if [[ -z $DOCKER_VERSION ]]; then
    if [[ $DOCKER_MODE == 1 && -z $APT_VERSION ]]; then
        echo "Docker is not installed."
        echo "Please install Docker and run this script again."
        echo ""
        echo "Exiting..."
        exit 1
    elif [[ $DOCKER_MODE != 1 && ! -z $APT_VERSION ]]; then
        echo "Docker is not installed."
        echo "You will not be able to build the kernel under Docker until it is installed."
        echo ""
        DOCKER_MODE=0
    fi
fi

# Check if we are run as root, and if so then set SUDO to empty
# If we are not run as root, then set SUDO to sudo
if [[ $EUID == 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

# For those wanting to use another tool than docker, allow the use of an alternative tool like podman
# If the user wants to use an alternative tool then set DOCKER to the name of the tool
# If the user does not want to use an alternative tool then set DOCKER to docker
DOCKER=${DOCKER:-docker}

install_prereqs() {
    echo "Installing prerequisites..."
    $SUDO apt update
    $SUDO apt install -y build-essential dwarves libncurses5-dev libssl-dev bison flex libelf-dev rsync curl python3
}

download_kernel() {
    tag_name=$(echo "linux-msft-wsl-$1")
    cd $KERNEL_BASE_PATH

    # If the tarball already exists then do not download it again
    # If the tarball does not exist then download it
    if [[ ! -f WSL2-Linux-Kernel.tar.gz ]]; then
        echo "Downloading WSL2-Linux-Kernel tag $tag_name..."
        curl -L -o WSL2-Linux-Kernel.tar.gz https://github.com/microsoft/WSL2-Linux-Kernel/archive/$tag_name.tar.gz
        echo "Download complete."
    else
        echo "WSL2-Linux-Kernel.tar.gz already exists. Skipping download."
    fi

    # If the tarball has already been extracted then do not extract it again
    # If the tarball has not been extracted then extract it
    if [[ ! -d WSL2-Linux-Kernel-$tag_name ]]; then
        echo "Extracting WSL2-Linux-Kernel..."
        tar -xzf WSL2-Linux-Kernel.tar.gz
        echo "Extraction complete."
    else
        echo "WSL2-Linux-Kernel-$tag_name already exists. Skipping extraction."
    fi
    KERNEL_BASE_PATH=$KERNEL_BASE_PATH/WSL2-Linux-Kernel-$tag_name
}

configure_kernel() {
    echo "Configuring kernel..."
    tag_name=$(echo "linux-msft-wsl-$1")
    cd $KERNEL_BASE_PATH
    echo "Do you want to use the default configuration from the repository (Y) or your current kernel configuration (N) ? (y/n)"
    while true; do
        read -p "Enter your choice: " choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            cp Microsoft/config-wsl .config
            break
        elif [[ $choice == "n" || $choice == "N" ]]; then
            zcat /proc/config.gz >.config
            break
        else
            echo "Invalid choice"
        fi
    done

    # Browse through the *.diff files in the current directory and show a menu to the user
    # to select the patches to apply.

    # diff files must be created using diff -u0 Microsoft/config-wsl .config > ../example.diff

    # since we forcibly have reset the .config file, we need to reset the applied patches array
    # this array will store the patches that have been applied
    # 0 means not applied
    # 1 means applied
    for ((i = 0; i < ${#patches[@]}; i++)); do
        applied_patches[$i]=0
    done

    # show menu from the patches array
    # the patches ar stored in the patches array that will need to have their first letter capitalized and the .diff extension removed and underscores replaced with spaces
    # Example: 1. Patch 1
    #          2. Patch 2
    #          3. Patch 3
    #          4. Patch 4
    #          5. Patch 5
    #          X. Return to main menu

    # The user can select the patches to apply by entering the numbers separated by space.
    # Example: 1 2 3 4 5
    while true; do
        echo ""
        echo "Select the patches to apply:"
        echo "============================"
        for ((i = 0; i < ${#patches[@]}; i++)); do
            local patch_name=${patches[$i]%.diff}
            # replace underscores with spaces and capitalize first letter of each word
            patch_name=$(echo "${patch_name//_/ }" | sed -e "s/\b\(.\)/\u\1/g")
            # show the patch name and if it is already applied then show a check mark
            if [[ ${applied_patches[$i]} == 0 ]]; then
                echo "$((i + 1)). ${patch_name}"
            else
                echo "$((i + 1)). ${patch_name} ✓"
            fi
        done
        echo "X. Return to main menu"
        echo ""
        read -p "Enter your choice: " choice
        if [[ $choice == "x" || $choice == "X" ]]; then
            break
        else
            # apply the patches
            for patch in $choice; do
                # patch the .config file with the selected patch
                patch .config < $SCRIPT_DIR/${patches[$((patch - 1))]}

                # if succesful then add the patch to the list of applied patches
                if [[ $? == 0 ]]; then
                    applied_patches[$((patch - 1))]=1
                fi
            done
        fi
    done
}

build_kernel() {
    tag_name=$(echo "linux-msft-wsl-$1")
    cd $KERNEL_BASE_PATH

    # to prevent overload on the system, we will use the number of cores - 1
    # if the number of cores is 1 then we will use 1 core

    # get the number of cores
    cores=$(nproc)
    # if the number of cores is not 1, assume it is more than 1
    if [[ $cores != 1 ]]; then
        # therefore use the number of cores - 1 to avoid overloading the system
        cores=$((cores - 1))
    fi

    echo "Building kernel using $cores cores..."
    make -j$cores
    echo "Build complete."
    echo "Building kernel modules..."
    make -j$cores modules
    echo "Installing kernel modules..."
    $SUDO make modules_install
}

make_deb() {
    tag_name=$(echo "linux-msft-wsl-$1")
    cd $KERNEL_BASE_PATH
    echo "Making Debian package..."
    $SUDO make bindeb-pkg
    echo "Debian package created."

    # Show information about the newly created Debian package using dpkg-deb -I and -c
    deb_file=$(ls ../linux-image-$1-microsoft-standard-wsl2_*.deb)
    echo "Information about the package:"
    echo ""
    dpkg-deb -I $deb_file
    echo ""
    echo "Contents of the package:"
    echo ""
    dpkg-deb -c $deb_file
    echo ""
    echo "The package is: $deb_file"
}

prep_wslconfig() {
    tag_name=$(echo "linux-msft-wsl-$1")

    # If we are running in Docker then destination of the kernel will be /usr/src/build
    # If we are not running in Docker then ask the user where they want to store the kernel
    destinationPath="/usr/src/build"
    if [[ $DOCKER_MODE != 1 ]]; then
        # ask the user where they want to store the kernel
        # if the user enters a path that does not exist then create the path
        # if the user enters a path that exists then use that path
        # path must be absolute
        echo "Enter the path where you want to store the kernel (absolute path):"
        read -p "Enter your choice: " destinationPath
    fi
    mkdir -p $destinationPath

    echo "Copying kernel files..."
    # copy the kernel files to the path
    cp -v $KERNEL_BASE_PATH/arch/x86/boot/bzImage $destinationPath/kernel-$1
    cp -v $KERNEL_BASE_PATH/.config $destinationPath/config-$1
    echo "Kernel files copied."

    # Create a new .wslconfig file in the destination path
    # let the user merge it with its own .wslconfig file

    echo "[wsl2]" >$destinationPath/.wslconfig
    echo "kernel=$destinationPath/kernel-$1" >>$destinationPath/.wslconfig

    echo "$destinationPath/.wslconfig contains these lines:"
    echo ""
    cat $destinationPath/.wslconfig
    echo ""
    echo "Feel free to copy the file or copy/paste its content to your Wiwndows %USERPROFILE% folder."
    echo "And run : wsl --shutdown"
    echo "Then restart WSL2."
}

run_in_docker() {
    cd $(dirname $0)
    echo "Using $DOCKER to build the kernel. If you want to use another tool, please set the DOCKER environment variable to the name of the tool."

    # Ask if the user wants to build the Docker image
    # If the user does not want to build the Docker image then try to run it as is
    # If the user wants to build the Docker image then build it and run it
    echo "Do you want to build the Docker image (Y) or use the existing image (N) ? (y/n)"
    while true; do
        read -p "Enter your choice: " choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            echo "Building the Docker image..."
            $DOCKER build -t wsl2-kernel-builder .
            echo "Docker image built."
            break
        elif [[ $choice == "n" || $choice == "N" ]]; then
            break
        else
            echo "Invalid choice"
        fi
    done
    echo "Running from Docker with filesystem map to $(pwd) ..."
    $DOCKER run -e DEBEMAIL=$DEBEMAIL -it --rm -v ./kernel:/usr/src/ wsl2-kernel-builder

    # In any case we force exit
    exit $?
}

current_kernel_version=$(uname -r | cut -d- -f1)
user_kernel_version=${1:-$current_kernel_version}
# get latest kernel version from github
latest_kernel_version=$(curl -s https://api.github.com/repos/microsoft/WSL2-Linux-Kernel/releases/latest | grep tag_name | cut -d: -f2 | tr -d \"\,v | cut -d- -f4)

echo "Welcome to WSL2 Kernel Builder"
echo "=============================="
echo "Current Kernel Version    : $current_kernel_version"
echo "Latest Kernel Version     : $latest_kernel_version"
echo ""
echo "We are going to use this  : $user_kernel_version"
echo ""
echo "If you want to change the kernel version, please pass the version as an argument to this script."
echo "Example: $0 $latest_kernel_version (if you want to build the latest version)"
echo ""
echo "Note: If you are building kernel for the first time, please make sure you already have the prerequisites."
echo ""

echo "Loading patches from $(pwd)"

# load patches names into an array
# patches must have been created using diff -u0 Microsoft/config-wsl .config > ../example.diff
i=0
for patch in *.diff; do
    patches[$i]=$patch
    i=$((i + 1))
done

# show number of patches loaded
echo "Loaded ${#patches[@]} patches"

while true; do
    echo ""
    echo "Build WSL Kernel"
    echo "================"
    echo "1. Download WSL2-Linux-Kernel"
    echo "2. Configure Kernel"
    echo "3. Build Kernel"
    echo "4. Make a Debian Package"
    echo "5. Prepare .wslconfig"

    if [[ -z $DOCKER_MODE || $DOCKER_MODE == 0 ]]; then
        echo "8. Install Prerequisites"
    fi
    if [[ -z $DOCKER_MODE ]]; then
        echo "9. Run in Docker"
    fi
    echo "0. Exit"

    read -p "Enter your choice: " choice

    case $choice in
    1) download_kernel $user_kernel_version ;;
    2) configure_kernel $user_kernel_version ;;
    3) build_kernel $user_kernel_version ;;
    4) make_deb $user_kernel_version ;;
    5) prep_wslconfig $user_kernel_version ;;
    8) install_prereqs ;;
    9) run_in_docker ;;
    0) exit ;;
    *) echo "Invalid choice" ;;
    esac
done
