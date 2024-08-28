DISTRO ?= fedora
ifeq ($(DISTRO), fedora)
	OS_VERSION = 40
        BASE_IMAGE = quay.io/fedora/fedora-bootc:$(OS_VERSION)
else ifeq ($(DISTRO), centos)
	OS_VERSION = stream9
        BASE_IMAGE = quay.io/centos-bootc/centos-bootc:stream9
else ifeq ($(DISTRO), rhel)
	OS_VERSION = 9.4
        BASE_IMAGE = registry.redhat.io/rhel9/rhel-bootc:9.4
        EXTRA_LABELS = --label=com.redhat.component=rhel-bootc-amd-rocm
        EXTRA_LABELS := $(EXTRA_LABELS) --label=com.redhat.license_terms="https://www.redhat.com/en/about/red-hat-end-user-license-agreements\#RHELBootcAmdRocm"
        EXTRA_LABELS := $(EXTRA_LABELS) --label=io.k8s.description="RHEL Bootc for AMD ROCm provides a container runtime for AMD ROCm accelerated workloads"
        EXTRA_LABELS := $(EXTRA_LABELS) --label=io.k8s.display-name="RHEL Bootc for AMD ROCm"
        EXTRA_LABELS := $(EXTRA_LABELS) --label=summary="Provides a container runtime for AMD ROCm accelerated workloads"
        UNSET_LABELS = --unsetlabel=release
        UNSET_LABELS := $(UNSET_LABELS) --unsetlabel=url
endif

CONTAINER_TOOL ?= podman
CONTAINER_TOOL_EXTRA_ARGS ?=
BUILD_ARG_FILE ?= argfile.conf
DRIVER_VERSION ?= $(shell [ -f ${BUILD_ARG_FILE} ] && (grep 'DRIVER_VERSION=' ${BUILD_ARG_FILE} | cut -d '=' -f 2))
CUDA_VERSION ?= $(shell [ -f ${BUILD_ARG_FILE} ] && (grep 'CUDA_VERSION=' ${BUILD_ARG_FILE} | cut -d '=' -f 2))

AUTH_JSON ?=

SOURCE_DATE_EPOCH ?= $(shell git log -1 --pretty=%ct)
VCS_REF ?= $(shell git rev-parse HEAD)

ARCH ?= $(shell arch)

KERNEL_VERSION ?= $(shell skopeo inspect --format json docker://${BASE_IMAGE} | jq -r '.Labels["ostree.linux"]' | sed "s/\.${ARCH}//")
DRIVER_TOOLKIT_IMAGE ?= quay.io/smgglrs-ai/driver-toolkit:$(KERNEL_VERSION)

REGISTRY ?= quay.io
REGISTRY_ORG ?= smgglrs-ai
IMAGE_NAME ?= ${DISTRO}-bootc-nvidia-cuda
IMAGE_TAG ?= $(OS_VERSION)-$(DRIVER_VERSION)-${CUDA_VERSION}
IMAGE ?= ${REGISTRY}/${REGISTRY_ORG}/${IMAGE_NAME}:${IMAGE_TAG}

default: build-container

.PHONY: build-container
build-container:
	echo "BASE_IMAGE: $(BASE_IMAGE)" ; \
	"${CONTAINER_TOOL}" build \
		$(ARCH:%=--platform linux/%) \
		$(BUILD_ARG_FILE:%=--build-arg-file=%) \
		$(SOURCE_DATE_EPOCH:%=--timestamp=%) \
		$(if $(SSH_PUBKEY),--build-arg SSHPUBKEY='$(SSH_PUBKEY)') \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg DRIVER_TOOLKIT_IMAGE=$(DRIVER_TOOLKIT_IMAGE) \
		--label org.opencontainers.image.version=${OS_VERSION}-${DRIVER_VERSION}-${CUDA_VERSION} \
		--label vcs-ref=${VCS_REF} \
		--label version=${OS_VERSION}-${DRIVER_VERSION}-${CUDA_VERSION} \
		--cap-add SYS_ADMIN \
		--file Containerfile \
		--security-opt label=disable \
		--tag "${IMAGE}" \
		--volume $(shell pwd)/repos.d:/tmp/repos.d:ro,Z \
		${CONTAINER_TOOL_EXTRA_ARGS} \
		.


.PHONY: push-container
push-container:
	"${CONTAINER_TOOL}" push "${IMAGE}"

.PHONY: build-iso
build-iso:
	echo "Building ISO image for ${IMAGE}"

.PHONY: push-iso
push-iso:
	echo "Pushing ISO image for ${IMAGE}"

.PHONY: build-raw
build-raw:
	echo "Building RAW image for ${IMAGE}"

.PHONY: push-raw
push-raw:
	echo "Pushing RAW image for ${IMAGE}"

.PHONY: build-aws
build-aws:
	echo "Building AWS image for ${IMAGE}"

.PHONY: push-iso
push-aws:
	echo "Pushing AWS image for ${IMAGE}"

.PHONY: build-azure
build-azure:
	echo "Building Azure image for ${IMAGE}"

.PHONY: push-azure
push-azure:
	echo "Pushing Azure image for ${IMAGE}"

.PHONY: build-gcp
build-gcp:
	echo "Building GCP image for ${IMAGE}"

.PHONY: push-gcp
push-gcp:
	echo "Pushing GCP image for ${IMAGE}"

.PHONY: build-qcow2
build-qcow2:
	echo "Building QCOW2 image for ${IMAGE}"

.PHONY: push-qcow2
push-qcow2:
	echo "Pushing QCOW2 image for ${IMAGE}"

.PHONY: build-vmware
build-vmware:
	echo "Building VMware image for ${IMAGE}"

.PHONY: push-vmware
push-vmware:
	echo "Pushing VMware image for ${IMAGE}"

.PHONY: all
all: build push build-iso push-iso image-raw image-aws
