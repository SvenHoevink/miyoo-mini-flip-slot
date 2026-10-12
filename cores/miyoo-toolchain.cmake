# CMake cross-compile settings for the Miyoo Mini Flip (SSD202D, armv7 Cortex-A7).
# Used by cores/mgba/build-miyoo.sh inside the miyoomini-toolchain container.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(TC /opt/miyoomini-toolchain)
set(CMAKE_C_COMPILER   ${TC}/usr/bin/arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER ${TC}/usr/bin/arm-linux-gnueabihf-g++)
set(CMAKE_SYSROOT      ${TC}/arm-linux-gnueabihf/libc)

# Cortex-A7 with NEON, hard float. armv7ve matches what gpSP's
# classic_armv7_a7 recipe uses, so both cores target the same ISA.
set(ARCH_FLAGS "-march=armv7ve -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard")
set(CMAKE_C_FLAGS_INIT   "${ARCH_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${ARCH_FLAGS}")

# Look for libraries and headers in the sysroot, never on the build host.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
