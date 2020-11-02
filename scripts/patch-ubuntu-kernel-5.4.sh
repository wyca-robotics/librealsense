#!/bin/bash

#Break execution on any error received
set -e

#trap read debug

echo -e "\e[36mDevelopment script for kernel 4.16 with metadata node\e[0m"

#Locally suppress stderr to avoid raising not relevant messages
exec 3>&2
exec 2> /dev/null
con_dev=$(ls /dev/video* | wc -l)
exec 2>&3

if [ $con_dev -ne 0 ];
then
        echo -e "\e[32m"
        read -p "Remove all RealSense cameras attached. Hit any key when ready"
        echo -e "\e[0m"
fi

#Include usability functions
source ./patch-utils.sh

# Get the required tools and headers to build the kernel
sudo apt-get install linux-headers-generic build-essential git
#Packages to build the patched modules / kernel 4.16
require_package libusb-1.0-0-dev
require_package libssl-dev
require_package bison
require_package flex
require_package libelf-dev


minor=$(uname -r | cut -d '.' -f 2)
if [ $minor -ne 4 ];
then
        echo -e "\e[43mThe patch is applicable for kernel version 5.4. \n/
        For earlier kernels please use patch-realsense-ubuntu-lts.sh script \e[0m"
        exit 1
fi

kernel_branch=$(uname -r | awk -F '[.-]' '{print "v"$1"."$2"."$3}')
kernel_major_minor=$(uname -r | awk -F '[.-]' '{print "v"$1"."$2}')
kernel_name="ubuntu-${ubuntu_codename}-$kernel_branch"

# Get the linux kernel and change into source tree
#[ ! -d ${kernel_name} ] && git clone git://git.launchpad.net/~ubuntu-kernel-test/ubuntu/+source/linux/+git/mainline-crack --depth 1 ./${kernel_name}

cd ${kernel_name}

# Verify that there are no trailing changes., warn the user to make corrective action if needed
if [ $(git status | grep 'modified:' | wc -l) -ne 0 ];
then
        echo -e "\e[36mThe kernel has modified files:\e[0m"
        git status | grep 'modified:'
        echo -e "\e[36mProceeding will reset all local kernel changes. Press 'n' within 10 seconds to abort the operation"
        set +e
        read -n 1 -t 10 -r -p "Do you want to proceed? [Y/n]" response
        set -e
        response=${response,,}    # tolower
        if [[ $response =~ ^(n|N)$ ]];
        then
                echo -e "\e[41mScript has been aborted on user requiest. Please resolve the modified files are rerun\e[0m"
                exit 1
        else
                echo -e "\e[0m"
                echo -e "\e[32mUpdate the folder content with the latest from mainline branch\e[0m"
                git fetch origin --depth 1
                printf "Resetting local changes in %s folder\n " ${kernel_name}
                git reset --hard
        fi
fi

## Patching kernel for RealSense devices
echo -e "\e[32mApplying realsense-uvc patch\e[0m"
patch -p1 < ../realsense-camera-formats-bionic-hwe-5.4.patch
echo -e "\e[32mApplying realsense-metadata patch\e[0m"
patch -p1 < ../realsense-metadata-bionic-hwe-5.4.patch
echo -e "\e[32mApplying realsense-hid patch\e[0m"
patch -p1 < ../realsense-hid-bionic-hwe-5.4.patch
echo -e "\e[32mApplying realsense-powerlinefrequency-fix patch\e[0m"
patch -p1 < ../realsense-powerlinefrequency-control-fix.patch

# Copy configuration
sudo cp /usr/src/linux-headers-$(uname -r)/.config .
sudo cp /usr/src/linux-headers-$(uname -r)/Module.symvers .

sudo make olddefconfig modules_prepare

#Vermagic identity is required
#IFS='.' read -a kernel_version <<< "$LINUX_BRANCH"
#sudo sed -i "s/\".*\"/\"$LINUX_BRANCH\"/g" ./include/generated/utsrelease.h
#sudo sed -i "s/.*/$LINUX_BRANCH/g" ./include/config/kernel.release
##Patch for Trusty Tahr (Ubuntu 14.05) with GCC not retrofitted with the retpoline patch.
#[ $retpoline_retrofit -eq 1 ] && sudo sed -i "s/#ifdef RETPOLINE/#if (1)/g" ./include/linux/vermagic.h


# Build the uvc, accel and gyro modules
KBASE=`pwd`
cd drivers/media/usb/uvc
sudo cp $KBASE/Module.symvers .

echo -e "\e[32mCompiling uvc module\e[0m"
sudo make -j -C $KBASE M=$KBASE/drivers/media/usb/uvc/ modules
echo -e "\e[32mCompiling accelerometer and gyro modules\e[0m"
sudo make -j -C $KBASE M=$KBASE/drivers/iio/accel modules
sudo make -j -C $KBASE M=$KBASE/drivers/iio/gyro modules
echo -e "\e[32mCompiling v4l2-core modules\e[0m"
sudo make -j -C $KBASE M=$KBASE/drivers/media/v4l2-core modules

