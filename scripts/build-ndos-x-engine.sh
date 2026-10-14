#!/bin/bash
set -euo pipefail
ndos_x_root=$(cd "$(dirname "$0")/.." && pwd)
ndos_x_sdk=${NDOS_X_SDK:-iphoneos}
ndos_x_arch=${NDOS_X_ARCH:-arm64}
case "$ndos_x_sdk" in iphoneos) ndos_x_target="$ndos_x_arch-apple-ios15.4" ;; iphonesimulator) ndos_x_target="$ndos_x_arch-apple-ios15.4-simulator" ;; *) echo "Unsupported SDK: $ndos_x_sdk" >&2; exit 1 ;; esac
case "$ndos_x_arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ndos_x_arch" >&2; exit 1 ;; esac
ndos_x_build="$ndos_x_root/output/ndos-x-engine/$ndos_x_sdk-$ndos_x_arch"
ndos_x_prefix="$ndos_x_build/prefix"
ndos_x_sysroot=$(xcrun --sdk "$ndos_x_sdk" --show-sdk-path)
ndos_x_jobs=${NDOS_X_JOBS:-8}
# Xcode's environment does not normally include Homebrew build tools.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
python3 "$ndos_x_root/scripts/prepare-ndos-x.py"
for ndos_x_tool in cmake autoconf make curl; do command -v "$ndos_x_tool" >/dev/null || { echo "Install required build tool: $ndos_x_tool" >&2; exit 1; }; done
if ! command -v automake >/dev/null; then
    ndos_x_tools="$ndos_x_root/output/ndos-x-tools"
    if [[ ! -x "$ndos_x_tools/bin/automake" ]]; then
        mkdir -p "$ndos_x_tools/bootstrap"
        curl --fail --location https://ftp.gnu.org/gnu/automake/automake-1.18.1.tar.xz -o "$ndos_x_tools/bootstrap/automake.tar.xz"
        ndos_x_actual=$(shasum -a 256 "$ndos_x_tools/bootstrap/automake.tar.xz" | cut -d' ' -f1)
        [[ "$ndos_x_actual" == 168aa363278351b89af56684448f525a5bce5079d0b6842bd910fdd3f1646887 ]] || { echo 'Automake checksum mismatch' >&2; exit 1; }
        tar -xf "$ndos_x_tools/bootstrap/automake.tar.xz" -C "$ndos_x_tools/bootstrap"
        (cd "$ndos_x_tools/bootstrap/automake-1.18.1" && ./configure --prefix="$ndos_x_tools" && make -j"$ndos_x_jobs" install)
    fi
    export PATH="$ndos_x_tools/bin:$PATH"
fi
mkdir -p "$ndos_x_build"
cmake -S "$ndos_x_root/vendor/SDL2" -B "$ndos_x_build/SDL2" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$ndos_x_sdk" -DCMAKE_OSX_ARCHITECTURES="$ndos_x_arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.4 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$ndos_x_prefix" \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL2_DISABLE_SDL2MAIN=ON \
    -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF -DSDL_POWER=OFF -DSDL_SENSOR=OFF -DSDL_LOCALE=OFF \
    -DSDL_METAL=OFF -DSDL_RENDER_METAL=OFF -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF
cmake --build "$ndos_x_build/SDL2" -j"$ndos_x_jobs"
cmake --install "$ndos_x_build/SDL2"
cmake -S "$ndos_x_root/vendor/dosbox-x/vs/libpng" -B "$ndos_x_build/libpng" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$ndos_x_sdk" -DCMAKE_OSX_ARCHITECTURES="$ndos_x_arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.4 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$ndos_x_prefix" \
    -DPNG_SHARED=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_ARM_NEON=off \
    -DZLIB_LIBRARY="$ndos_x_sysroot/usr/lib/libz.tbd" -DZLIB_INCLUDE_DIR="$ndos_x_sysroot/usr/include"
cmake --build "$ndos_x_build/libpng" -j"$ndos_x_jobs"
cmake --install "$ndos_x_build/libpng"
# Autotools generation changes only upstream-ignored build files.
if [[ ! -f "$ndos_x_root/vendor/dosbox-x/configure" ]]; then
    (cd "$ndos_x_root/vendor/dosbox-x" && sh autogen.sh)
fi
mkdir -p "$ndos_x_build/dosbox-x"
export CC="$(xcrun --sdk "$ndos_x_sdk" --find clang) -target $ndos_x_target -isysroot $ndos_x_sysroot"
export CXX="$(xcrun --sdk "$ndos_x_sdk" --find clang++) -target $ndos_x_target -isysroot $ndos_x_sysroot"
export CFLAGS='-O2 -DNDOS_X_HOST -D_DARWIN_C_SOURCE'
export CXXFLAGS='-O2 -DSDL_MAIN_HANDLED -DNDOS_X_HOST -D_DARWIN_C_SOURCE'
export CPPFLAGS="-I$ndos_x_prefix/include" LDFLAGS="-L$ndos_x_prefix/lib"
export PKG_CONFIG_LIBDIR="$ndos_x_prefix/lib/pkgconfig" PKG_CONFIG_PATH=
export SDL2_CONFIG="$ndos_x_prefix/bin/sdl2-config"
if [[ "$ndos_x_arch" == arm64 ]]; then ndos_x_host=aarch64-apple-ios; else ndos_x_host=x86_64-apple-ios; fi
ndos_x_signature=$(cat "$ndos_x_root/Experimental/dependencies.json" "$0" "$ndos_x_root"/Patches/ndos-x/dosbox-x/*.patch | shasum -a 256 | cut -d' ' -f1)
if [[ ! -f "$ndos_x_build/dosbox-x/.ndos-x-configuration" ]] || [[ "$(cat "$ndos_x_build/dosbox-x/.ndos-x-configuration")" != "$ndos_x_signature" ]]; then
    (cd "$ndos_x_build/dosbox-x" && "$ndos_x_root/vendor/dosbox-x/configure" \
        --host="$ndos_x_host" --enable-sdl2 --disable-sdl2test --disable-sdltest \
        --disable-opengl --disable-gamelink --disable-sdlnet --disable-x11 \
        --disable-dynamic-core --disable-dynamic-x86 --disable-dynrec --disable-fpu-x86 --disable-fpu-x64 \
        --disable-freetype --disable-printer --disable-xbrz --disable-mt32 --disable-screenshots \
        --disable-libslirp --disable-libfluidsynth --disable-avcodec)
    printf '%s\n' "$ndos_x_signature" > "$ndos_x_build/dosbox-x/.ndos-x-configuration"
fi
make -C "$ndos_x_build/dosbox-x/src" -j"$ndos_x_jobs" dosbox.o
for ndos_x_component in cpu debug dos fpu gui hardware libs ints misc shell builtin platform aviwriter output agent; do
    make -C "$ndos_x_build/dosbox-x/src/$ndos_x_component" -j"$ndos_x_jobs"
done
# The upstream Apple PhysicsFS backend already supports iOS, but its Automake
# source membership is conditional on desktop MACOSX. Compile it explicitly.
$(xcrun --sdk "$ndos_x_sdk" --find clang++) -target "$ndos_x_target" -isysroot "$ndos_x_sysroot" \
    -std=gnu++14 -O2 -DNDOS_X_HOST -D_DARWIN_C_SOURCE -c \
    "$ndos_x_root/vendor/dosbox-x/src/libs/physfs/physfs_platform_apple.mm" \
    -o "$ndos_x_build/physfs_apple.o"
# Combine the upstream archive membership, preserving its source selection.
ndos_x_archives=()
while IFS= read -r ndos_x_archive; do ndos_x_archives+=("$ndos_x_archive"); done < <(find "$ndos_x_build/dosbox-x/src" -name '*.a' -type f | sort)
/usr/bin/libtool -static -o "$ndos_x_build/libdosbox-x.a" "$ndos_x_build/dosbox-x/src/dosbox.o" "$ndos_x_build/physfs_apple.o" "${ndos_x_archives[@]}"
echo "Built $ndos_x_build/libdosbox-x.a"
