FROM debian:bullseye-slim

# Copy source code
WORKDIR /root
COPY build_kernel.sh ./
COPY *.diff ./
ENV DOCKER_MODE=1
ENV KERNEL_BASE_PATH /usr/src/linux

# By default run the build script
CMD ["/root/build_kernel.sh"]

# Install dependencies
RUN apt update && \
    apt install -y build-essential bc kmod cpio flex libncurses5-dev libelf-dev libssl-dev dwarves bison rsync curl python3
