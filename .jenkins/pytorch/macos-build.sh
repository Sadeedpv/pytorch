#!/bin/bash

# shellcheck disable=SC2034
# shellcheck source=./macos-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/macos-common.sh"

# Build PyTorch
if [ -z "${IN_CI}" ]; then
  export DEVELOPER_DIR=/Applications/Xcode9.app/Contents/Developer
fi

# This helper function wraps calls to binaries with sccache, but only if they're not already wrapped with sccache.
# For example, `clang` will be `sccache clang`, but `sccache clang` will not become `sccache sccache clang`.
# The way this is done is by detecting the command of the parent pid of the current process and checking whether
# that is sccache, and wrapping sccache around the process if its parent were not already sccache.
function write_sccache_stub() {
  output=$1
  binary=$(basename "${output}")

  printf "#!/bin/sh\nif [ \$(ps auxc \$(ps auxc -o ppid \$\$ | grep \$\$ | rev | cut -d' ' -f1 | rev) | tr '\\\\n' ' ' | rev | cut -d' ' -f2 | rev) != sccache ]; then\n  exec sccache %s \"\$@\"\nelse\n  exec %s \"\$@\"\nfi" "$(which "${binary}")" "$(which "${binary}")" > "${output}"
  chmod a+x "${output}"
}

if which sccache > /dev/null; then
  # Create temp directory for sccache shims
  tmp_dir=$(mktemp -d)
  trap 'rm -rfv ${tmp_dir}' EXIT
  write_sccache_stub "${tmp_dir}/clang++"
  write_sccache_stub "${tmp_dir}/clang"

  export PATH="${tmp_dir}:$PATH"
fi

cross_compile_arm64() {
  # Cross compilation for arm64
  USE_DISTRIBUTED=1 CMAKE_OSX_ARCHITECTURES=arm64 MACOSX_DEPLOYMENT_TARGET=11.0 USE_MKLDNN=OFF USE_NNPACK=OFF USE_QNNPACK=OFF BUILD_TEST=OFF python setup.py bdist_wheel
}

compile_x86_64() {
  USE_DISTRIBUTED=1 USE_NNPACK=OFF python setup.py bdist_wheel
}

build_lite_interpreter() {
    echo "Testing libtorch (lite interpreter)."

    CPP_BUILD="$(pwd)/../cpp_build"
    # Ensure the removal of the tmp directory
    trap 'rm -rfv ${CPP_BUILD}' EXIT
    rm -rf "${CPP_BUILD}"
    mkdir -p "${CPP_BUILD}/caffe2"

    # It looks libtorch need to be built in "${CPP_BUILD}/caffe2 folder.
    BUILD_LIBTORCH_PY=$PWD/tools/build_libtorch.py
    pushd "${CPP_BUILD}/caffe2" || exit
    VERBOSE=1 DEBUG=1 python "${BUILD_LIBTORCH_PY}"
    popd || exit

    "${CPP_BUILD}/caffe2/build/bin/test_lite_interpreter_runtime"
}

if [[ ${BUILD_ENVIRONMENT} = *arm64* ]]; then
  cross_compile_arm64
elif [[ ${BUILD_ENVIRONMENT} = *lite-interpreter* ]]; then
  export BUILD_LITE_INTERPRETER=1
  build_lite_interpreter
else
  compile_x86_64
fi

assert_git_not_dirty
