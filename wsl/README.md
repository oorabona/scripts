# WSL2 Linux Kernel build

This script will build the WSL2 Linux kernel from the source code provided by Microsoft.

It is made to be run in a Debian compatible environment (including Ubuntu) and will install all the required dependencies if asked to.

Otherwise, it can build a local Docker container image and run the build inside it.

## Usage

```bash
./build_kernel.sh [version]
```

The only argument is the version of the kernel to build. It must be a version from the [linux-msft-wsl](https://github.com/microsoft/WSL2-Linux-Kernel) repository. Note that the script will automatically add the `v` prefix and the `linux-msft-wsl-` so that you do not have to.

If no argument is provided, the script will build the latest version.

## Example

```bash
./build_kernel 4.19.121
```

## Docker

If you do not want to install the dependencies on your system, you can build the kernel inside a Docker container.

```bash
docker build -t wsl2-kernel-builder .
docker run -e DEBEMAIL=$DEBEMAIL -it --rm -v ./kernel:/usr/src/ wsl2-kernel-builder
```

The `DEBEMAIL` environment variable is used to set the maintainer email address for the package.

The kernel will be built in the `kernel` directory. All the required subdirectories will be created automatically.

## Buid Steps

1. Start off by downloading the kernel from GitHub, this is done with menu option #1.
2. Then, you can apply patches to the kernel with menu option #2.
3. Finally, you can build the kernel with menu option #3.

If you want to build the Debian package, you can do so with menu option #4.
Preparing the .wslconfig file is done with menu option #5.

> Note that it will not create the file in the Windows %USERPROFILE% directory for you.
> It will only move all the required files in the `kernel` directory.
> You will have to copy them over to the Windows side yourself, and adjust the paths in the .wslconfig file.

## Patches

The script will automatically load the patches from its own directory.
Feel free to submit a pull request if you want to add a patch.

The patches are listed in the menu and you can select which ones you want to apply.
The patches are only against the `.config` file, so they will not apply cleanly if you change the configuration.

If you want to create your own patches, use the following command:

```bash
diff -u0 Microsoft/config-wsl .config | grep -v "^[+-]{3}" > ../example.diff
```

## Building the kernel

The script will ask you whether you want to start from the configuration of your current kernel or from Microsoft's default configuration.

It will then build the kernel using all the available cores on your system, minus 1 to maintain some responsiveness.

## Installation of the kernel

The script will create a Debian package that can be installed on your system.

```bash
sudo dpkg -i linux-image-*.deb
```

## Feedback

If you have any feedback, feel free to open an issue or a pull request.
