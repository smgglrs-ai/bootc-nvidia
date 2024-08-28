ARG DRIVER_TOOLKIT_IMAGE="quay.io/ai-lab/nvidia-builder:latest"
ARG BASE_IMAGE="quay.io/centos-bootc/centos-bootc:stream9"

FROM ${DRIVER_TOOLKIT_IMAGE} as builder

ARG BASE_URL='https://us.download.nvidia.com/tesla'
ARG CUDA_REPO_BASE_URL='https://developer.download.nvidia.com/compute/cuda/repos'

ARG DRIVER_VERSION=

USER builder

WORKDIR /home/builder
COPY --chown=1001:0 x509-configuration.ini x509-configuration.ini

RUN export DISTRO=$(grep '^ID=' /etc/os-release | cut -d '=' -f 2 | sed 's/"//g') \
    && export KVER=$(rpm -q --qf "%{VERSION}" kernel-core) \
    && export KREL=$(rpm -q --qf "%{RELEASE}" kernel-core | sed 's/\.el.\(_.\)*$//') \
    && export KDIST=$(rpm -q --qf "%{RELEASE}" kernel-core | awk -F '.' '{ print "."$NF}') \
    && export OS_VERSION_MAJOR=$(grep "^VERSION=" /etc/os-release | cut -d '=' -f 2 | sed 's/"//g' | cut -d '.' -f 1) \
    && export BUILD_ARCH=$(arch) \
    && export TARGET_ARCH=$(echo "${BUILD_ARCH}" | sed 's/+64k//') \
    && export CUDA_REPO_ARCH=${TARGET_ARCH} \
    && if [ "${TARGET_ARCH}" == "aarch64" ]; then CUDA_REPO_ARCH="sbsa"; fi \
    && export DRIVER_STREAM=$(echo ${DRIVER_VERSION} | cut -d '.' -f 1) \
    && export DRIVER_RPM_FILENAME="kmod-nvidia-${DRIVER_VERSION}-${KVER}-${KREL}-${DRIVER_VERSION}-3${KDIST}.${TARGET_ARCH}.rpm" \
    && export DRIVER_RPM_URL="${CUDA_REPO_BASE_URL}/${DISTRO}${OS_VERSION_MAJOR}/${CUDA_REPO_ARCH}/${DRIVER_RPM_FILENAME}" \
    && if (($(curl -sLI "${DRIVER_RPM_URL}" | grep -E "^HTTP" | awk -F " " '{ print $2; }') == 200)) ; then \
        curl -sL -o "/home/builder/${DRIVER_RPM_FILENAME}" "${DRIVER_RPM_URL}" ; \
    else \
        git clone --depth 1 --single-branch -b rhel${OS_VERSION_MAJOR} https://github.com/NVIDIA/yum-packaging-precompiled-kmod \
        && cd yum-packaging-precompiled-kmod \
        && mkdir BUILD BUILDROOT RPMS SRPMS SOURCES SPECS \
        && mkdir nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH} \
        && curl -sLOf ${BASE_URL}/${DRIVER_VERSION}/NVIDIA-Linux-${TARGET_ARCH}-${DRIVER_VERSION}.run \
        && sh ./NVIDIA-Linux-${TARGET_ARCH}-${DRIVER_VERSION}.run --extract-only --target tmp \
        && mv tmp/kernel-open nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH}/kernel \
        && tar -cJf SOURCES/nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH}.tar.xz nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH} \
        && mv kmod-nvidia.spec SPECS/ \
        && openssl req -x509 -new -nodes -utf8 -sha256 -days 36500 -batch \
            -config ${HOME}/x509-configuration.ini \
            -outform DER -out SOURCES/public_key.der \
            -keyout SOURCES/private_key.priv \
        && rpmbuild \
            --define "% _arch ${BUILD_ARCH}" \
            --define "%_topdir $(pwd)" \
            --define "debug_package %{nil}" \
            --define "kernel ${KVER}" \
            --define "kernel_release ${KREL}" \
            --define "kernel_dist ${KDIST}" \
            --define "driver ${DRIVER_VERSION}" \
            --define "driver_branch ${DRIVER_STREAM}" \
            --define "vendor ${VENDOR:-undefined}" \
            --define "_buildhost ${RPM_HOST:-${HOSTNAME}}" \
            -v -bb SPECS/kmod-nvidia.spec \
        && mv RPMS/*/*.rpm /home/builder ; \
    fi

FROM ${BASE_IMAGE}

ARG BASE_URL='https://us.download.nvidia.com/tesla'

ARG DRIVER_TYPE=passthrough
ENV NVIDIA_DRIVER_TYPE=${DRIVER_TYPE}

ARG DRIVER_VERSION=
ENV NVIDIA_DRIVER_VERSION=${DRIVER_VERSION}
ARG CUDA_VERSION=

ARG TARGET_ARCH=''
ENV TARGETARCH=${TARGET_ARCH}

# Disable vGPU version compatibility check by default
ARG DISABLE_VGPU_VERSION_CHECK=true
ENV DISABLE_VGPU_VERSION_CHECK=$DISABLE_VGPU_VERSION_CHECK

USER root

COPY build/usr /usr

RUN --mount=type=bind,from=builder,source=/,destination=/tmp/builder,ro \
    export DISTRO=$(grep '^ID=' /etc/os-release | cut -d '=' -f 2 | sed 's/"//g') \
    && export BUILD_ARCH=$(arch) \
    && export TARGET_ARCH=$(echo "${BUILD_ARCH}" | sed 's/+64k//') \
    && ls /tmp/builder/home/builder/ \
    && mv /etc/selinux /etc/selinux.tmp \
    && export OS_VERSION_MAJOR=$(grep "^VERSION=" /etc/os-release | cut -d '=' -f 2 | sed 's/"//g' | cut -d '.' -f 1) \
    && export DRIVER_STREAM=$(echo ${DRIVER_VERSION} | cut -d '.' -f 1) \
    && export CUDA_VERSION_ARRAY=(${CUDA_VERSION//./ }) \
    && export CUDA_DASHED_VERSION=${CUDA_VERSION_ARRAY[0]}-${CUDA_VERSION_ARRAY[1]} \
    && export CUDA_REPO_ARCH=${TARGET_ARCH} \
    && if [ "${TARGET_ARCH}" == "aarch64" ]; then CUDA_REPO_ARCH="sbsa"; fi \
    && cp /tmp/repos.d/${DISTRO}/${TARGET_ARCH}/*.repo /etc/yum.repos.d/ \
    && cp /tmp/repos.d/${DISTRO}/${TARGET_ARCH}/RPM-GPG-KEY-NVIDIA-CUDA-${OS_VERSION_MAJOR} /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA-CUDA-${OS_VERSION_MAJOR} \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA-CUDA-${OS_VERSION_MAJOR} \
    && cp -a /etc/dnf/dnf.conf{,.tmp} && mv /etc/dnf/dnf.conf{.tmp,} \
    && dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save \
    && dnf -y module enable nvidia-driver:${DRIVER_STREAM}/default \
    && dnf update -y --exclude=kernel* \
    && dnf install -y \
        /tmp/builder/home/builder/kmod-nvidia-${DRIVER_VERSION}-*.rpm \
        nvidia-driver-${DRIVER_VERSION} \
        nvidia-driver-cuda-${DRIVER_VERSION} \
        nvidia-driver-libs-${DRIVER_VERSION} \
        nvidia-driver-NVML-${DRIVER_VERSION} \
        cuda-compat-${CUDA_DASHED_VERSION} \
        cuda-cudart-${CUDA_DASHED_VERSION} \
        nvidia-persistenced-${DRIVER_VERSION} \
        nvidia-container-toolkit \
        pciutils \
        rsync \
	skopeo \
        tmux \
    && if [ "$DRIVER_TYPE" != "vgpu" ] && [ "$TARGET_ARCH" != "arm64" ]; then \
        versionArray=(${DRIVER_VERSION//./ }); \
        DRIVER_BRANCH=${versionArray[0]}; \
        dnf module enable -y nvidia-driver:${DRIVER_BRANCH} && \
        dnf install -y nvidia-fabric-manager-${DRIVER_VERSION} libnvidia-nscq-${DRIVER_BRANCH}-${DRIVER_VERSION} ; \
    fi \
    && if [ "${DISTRO}" == "rhel" ]; then \
        dnf install -y rhc rhc-worker-playbook ; \
        rm -f /usr/lib/systemd/system/default.target.wants/bootc-fetch-apply-updates.timer ; \
    fi \
    && dnf clean all \
    && mv /etc/selinux.tmp /etc/selinux \
    && echo "blacklist nouveau" > /etc/modprobe.d/blacklist_nouveau.conf \
    && sed -i '/\[Unit\]/a ConditionDirectoryNotEmpty=/proc/driver/nvidia-nvswitch/devices' /usr/lib/systemd/system/nvidia-fabricmanager.service \
    && ln -s ../nvidia-fabricmanager.service /usr/lib/systemd/system/multi-user.target.wants/nvidia-fabricmanager.service \
    && ln -s ../nvidia-persistenced.service /usr/lib/systemd/system/multi-user.target.wants/nvidia-persistenced.service

ARG SSHPUBKEY

# The --build-arg "SSHPUBKEY=$(cat ~/.ssh/id_rsa.pub)" option inserts your
# public key into the image, allowing root access via ssh.
RUN if [ -n "${SSHPUBKEY}" ]; then \
    set -eu; mkdir -p /usr/ssh && \
        echo 'AuthorizedKeysFile /usr/ssh/%u.keys .ssh/authorized_keys .ssh/authorized_keys2' >> /etc/ssh/sshd_config.d/30-auth-system.conf && \
	    echo ${SSHPUBKEY} > /usr/ssh/root.keys && chmod 0600 /usr/ssh/root.keys; \
fi

# Setup /usr/lib/containers/storage as an additional store for images.
# Remove once the base images have this set by default.
# Also make sure not to duplicate if a base image already has it specified.
RUN grep -q /usr/lib/containers/storage /etc/containers/storage.conf || \
    sed -i -e '/additionalimage.*/a "/usr/lib/containers/storage",' \
	/etc/containers/storage.conf

# Added for running as an OCI Container to prevent Overlay on Overlay issues.
VOLUME /var/lib/containers

LABEL description="Bootc for AMD ROCm provides a container runtime for AMD ROCm accelerated workloads" \
      name="bootc-amd-rocm" \
      org.opencontainers.image.name="bootc-amd-rocm" \
      vcs-ref="${VCS_REF}"
