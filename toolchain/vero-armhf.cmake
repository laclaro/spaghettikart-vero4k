# CMake toolchain: Vero 4k+ (Amlogic S905X, Cortex-A53, Mali-450), OSMC Debian bullseye armhf userspace.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(CMAKE_SYSROOT /opt/vero-sysroot)

set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)
set(CMAKE_ASM_COMPILER arm-linux-gnueabihf-gcc)

# 32-bit code tuned for the Cortex-A53 cores.
set(_vero_cpu_flags "-mcpu=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard")
set(CMAKE_C_FLAGS_INIT "${_vero_cpu_flags}")
set(CMAKE_CXX_FLAGS_INIT "${_vero_cpu_flags}")
set(CMAKE_ASM_FLAGS_INIT "${_vero_cpu_flags}")

# GLES/EGL must come from the Mali blob in /opt/vero3/lib (soname libMali.so), the same
# driver the Vero's SDL2 mali-fbdev backend loads, not the mesa/glvnd stubs in /usr/lib.
# -L on the command line wins over the default search dirs for -lGLESv2 / -lEGL.
set(_vero_link_flags "-L${CMAKE_SYSROOT}/opt/vero3/lib -Wl,-rpath,/opt/vero3/lib")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_vero_link_flags}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_vero_link_flags}")
set(OPENGLES_LIBRARY "${CMAKE_SYSROOT}/opt/vero3/lib/libGLESv2.so" CACHE FILEPATH "")
set(OPENGL_gles2_LIBRARY "${CMAKE_SYSROOT}/opt/vero3/lib/libGLESv2.so" CACHE FILEPATH "")
set(OPENGL_gles3_LIBRARY "${CMAKE_SYSROOT}/opt/vero3/lib/libGLESv2.so" CACHE FILEPATH "")
set(OPENGL_egl_LIBRARY "${CMAKE_SYSROOT}/opt/vero3/lib/libEGL.so" CACHE FILEPATH "")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
