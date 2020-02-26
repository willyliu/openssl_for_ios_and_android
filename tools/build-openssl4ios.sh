#!/bin/bash
#
# Copyright 2016 leenjewel
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -u

SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
pwd_path="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
 
# Setup architectures, library name and other vars + cleanup from previous runs
# building arm64 will actually build arm64,armv7s,armv7
ARCHS=("arm64" "i386" "x86_64")
SDKS=("iphoneos" "iphonesimulator" "iphonesimulator")
PLATFORMS=("iPhoneOS" "iPhoneSimulator" "iPhoneSimulator")

DEVELOPER=`xcode-select -print-path`
# If you can't compile with this version, please modify the version to it which on your mac.
SDK_VERSION=""13.2""
MIN_IOS_VERSION="8.0"
LIB_NAME="openssl-1.1.1c"
LIB_DEST_DIR="${pwd_path}/../output/ios/openssl-universal"
HEADER_DEST_DIR="include"
rm -rf "${HEADER_DEST_DIR}" "${LIB_DEST_DIR}" "${LIB_NAME}"

# Unarchive library, then configure and make for specified architectures
configure_make()
{
   ARCH=$1; SDK=$2; PLATFORM=$3;
   if [ -d "${LIB_NAME}" ]; then
       rm -fr "${LIB_NAME}"
   fi
   tar xfz "${LIB_NAME}.tar.gz"
   pushd .; cd "${LIB_NAME}";

   if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
       echo ""
   else
       sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
   fi

   patch -b -p1 < "${pwd_path}/openssl-1.1.1c.patch"

   export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
   export CROSS_SDK="${PLATFORM}${SDK_VERSION}.sdk"
   export TOOLS="${DEVELOPER}"


   PREFIX_DIR="${pwd_path}/../output/ios/openssl-${ARCH}"
   if [ -d "${PREFIX_DIR}" ]; then
       rm -fr "${PREFIX_DIR}"
   fi
   mkdir -p "${PREFIX_DIR}"

   if [[ "${ARCH}" == "x86_64" ]]; then
        export CC="${TOOLS}/usr/bin/gcc -arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${MIN_IOS_VERSION} -mios-version-min=${MIN_IOS_VERSION} -DOPENSSL_NO_ASYNC"
        ./Configure darwin64-x86_64-cc no-shared no-weak-ssl-ciphers no-asm no-async no-engine --prefix="${PREFIX_DIR}"
   elif [[ "${ARCH}" == "i386" ]]; then
        export CC="${TOOLS}/usr/bin/gcc -arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${MIN_IOS_VERSION} -mios-version-min=${MIN_IOS_VERSION} -DOPENSSL_NO_ASYNC"
        export LDFLAGS="-Wl,-no_compact_unwind"
        ./Configure darwin-i386-cc no-shared no-weak-ssl-ciphers no-asm no-async no-engine --prefix="${PREFIX_DIR}"
   else
        ./Configure ios-cross no-shared no-weak-ssl-ciphers no-asm no-async no-engine --prefix="${PREFIX_DIR}"
        unset CC
        unset CFLAGS
        unset LDFLAGS
        sed -i "" 's/CC=$(CROSS_COMPILE)cc/CC=clang/g' Makefile
        sed -i "" "s:CFLAGS=-O3:CFLAGS=-O3 -arch arm64 -arch armv7 -arch armv7s -miphoneos-version-min=${MIN_IOS_VERSION} -mios-version-min=${MIN_IOS_VERSION} -DOPENSSL_NO_ASYNC -fembed-bitcode:g" Makefile
        sed -i "" 's/MAKEDEPEND=$(CROSS_COMPILE)cc/MAKEDEPPROG=$(CC) -M/g' Makefile
   fi

   if [ ! -d ${CROSS_TOP}/SDKs/${CROSS_SDK} ]; then
       echo "ERROR: iOS SDK version:'${SDK_VERSION}' incorrect, SDK in your system is:"
       xcodebuild -showsdks | grep iOS
       exit -1
   fi
   
   make clean
   if make -j8
   then
       make install_sw;
       make install_ssldirs;
       popd;
       rm -fr "${LIB_NAME}"
   fi
}
# for ((i=0; i < ${#ARCHS[@]}; i++))
for ((i=0; i < 1; i++))
do
    if [[ $# -eq 0 || "$1" == "${ARCHS[i]}" ]]; then
        configure_make "${ARCHS[i]}" "${SDKS[i]}" "${PLATFORMS[i]}"
    fi
done

# Combine libraries for different architectures into one
# Use .a files from the temp directory by providing relative paths
create_lib()
{
   LIB_SRC=$1; LIB_DST=$2;
   LIB_PATHS=( "${ARCHS[@]/#/${pwd_path}/../output/ios/openssl-}" )
   LIB_PATHS=( "${LIB_PATHS[@]/%//lib/${LIB_SRC}}" )
   lipo ${LIB_PATHS[@]} -create -output "${LIB_DST}"
}
mkdir "${LIB_DEST_DIR}";
create_lib "libcrypto.a" "${LIB_DEST_DIR}/libcrypto.a"
create_lib "libssl.a" "${LIB_DEST_DIR}/libssl.a"
lipo -info "${LIB_DEST_DIR}/libcrypto.a" "${LIB_DEST_DIR}/libssl.a"