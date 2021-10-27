#!/bin/sh
# ----------------------------
# Copyright 2021 Diskuv, Inc.
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
# ----------------------------
#
# @jonahbeckford: 2021-10-26
# - This file is licensed differently than the rest of the Diskuv OCaml distribution.
#   Keep the Apache License in this file since this file is part of the reproducible
#   build files.
#
######################################
# reproducible-compile-ocaml-functions.sh
#
# Purpose:
# 1. Provide common functions to be sourced in the reproducible step scripts.
#
# -------------------------------------------------------

# Most of this section was adapted from
# https://github.com/ocaml/opam/blob/012103bc52bfd4543f3d6f59edde91ac70acebc8/shell/bootstrap-ocaml.sh
# with portable shell linting (shellcheck) fixes applied.

windows_configure_and_define_make() {
  windows_configure_and_define_make_HOST="$1"
  shift
  windows_configure_and_define_make_PREFIX="$1"
  shift
  windows_configure_and_define_make_PATH_PREPEND="$1"
  shift
  windows_configure_and_define_make_LIB_PREPEND="$1"
  shift
  windows_configure_and_define_make_INC_PREPEND="$1"
  shift
  windows_configure_and_define_make_EXTRA_OPTS="$1"
  shift

  case "$(uname -m)" in
    'i686')
      windows_configure_and_define_make_BUILD=i686-pc-cygwin
    ;;
    'x86_64')
      windows_configure_and_define_make_BUILD=x86_64-pc-cygwin
    ;;
  esac

  # 4.13+ have --with-flexdll ./configure option. Autoselect it.
  windows_configure_and_define_make_OCAMLVER=$(awk 'NR==1{print}' VERSION)
  windows_configure_and_define_make_MAKEFLEXDLL=OFF
  case "$windows_configure_and_define_make_OCAMLVER" in
    4.00.*|4.01.*|4.02.*|4.03.*|4.04.*|4.05.*|4.06.*|4.07.*|4.08.*|4.09.*|4.10.*|4.11.*|4.12.*)
      windows_configure_and_define_make_MAKEFLEXDLL=ON
      ;;
    *)
      windows_configure_and_define_make_EXTRA_OPTS="$windows_configure_and_define_make_EXTRA_OPTS --with-flexdll"
      ;;
  esac

  windows_configure_and_define_make_WINPREFIX=$(printf "%s\n" "${windows_configure_and_define_make_PREFIX}" | cygpath -f - -m)
  # shellcheck disable=SC2086
  with_environment_for_ocaml_configure \
    PATH="${windows_configure_and_define_make_PATH_PREPEND}${windows_configure_and_define_make_PREFIX}/bin:${PATH}" \
    Lib="${windows_configure_and_define_make_LIB_PREPEND}${Lib:-}" \
    Include="${windows_configure_and_define_make_INC_PREPEND}${Include:-}" \
    ./configure --prefix "$windows_configure_and_define_make_WINPREFIX" \
                --build=$windows_configure_and_define_make_BUILD --host="$windows_configure_and_define_make_HOST" \
                --disable-stdlib-manpages \
                $windows_configure_and_define_make_EXTRA_OPTS
  if [ ! -e flexdll ]; then # OCaml 4.13.x has a git submodule for flexdll
    tar -xzf flexdll.tar.gz
    rm -rf flexdll
    mv flexdll-* flexdll
  fi

  # Define make functions
  if [ "$windows_configure_and_define_make_MAKEFLEXDLL" = ON ]; then
    OCAML_CONFIGURE_NEEDS_MAKE_FLEXDLL=ON
  else
    # shellcheck disable=SC2034
    OCAML_CONFIGURE_NEEDS_MAKE_FLEXDLL=OFF
  fi
  ocaml_make() {
    PATH="${windows_configure_and_define_make_PATH_PREPEND}${windows_configure_and_define_make_PREFIX}/bin:${PATH}" \
    Lib="${windows_configure_and_define_make_LIB_PREPEND}${Lib:-}" \
    Include="${windows_configure_and_define_make_INC_PREPEND}${Include:-}" \
    ${MAKE:-make} "$@"
  }
}

ocaml_configure() {
  ocaml_configure_PREFIX="$1"
  shift
  ocaml_configure_ARCH="$1"
  shift
  ocaml_configure_ABI="$1"
  shift
  ocaml_configure_EXTRA_OPTS="$1"
  shift

  # Compiler
  # --------

  if [ -x /usr/bin/cygpath ]; then
    # We will use MSVS to detect Visual Studio
    with_environment_for_ocaml_configure() {
      env "$@"
    }
    # There is a nasty bug (?) with MSYS2's dash.exe (probably _all_ dash) which will not accept the 'ProgramFiles(x86)' environment,
    # presumably because of the parentheses in it may or may not violate the POSIX standard. Typically that means that dash cannot
    # propagate that variable to a subprocess like bash or another dash.
    # So we use `cygpath -w --folder 42` which gets the value of CSIDL_PROGRAM_FILESX86.
    msvs_detect() {
      msvs_detect_PF86=$(/usr/bin/cygpath -w --folder 42)
      if [ -n "${msvs_detect_PF86}" ]; then
        env 'ProgramFiles(x86)'="$msvs_detect_PF86" ./msvs-detect "$@"
      else
        ./msvs-detect "$@"
      fi
    }
  else
    # We will be using the operating system C compiler
    with_environment_for_ocaml_configure() {
      env "$@"
    }
    msvs_detect() {
      ./msvs-detect "$@"
    }
  fi

  # ./configure and define make functions
  # -------------------------------------

  if [ -n "$ocaml_configure_ABI" ] && [ -n "${COMSPEC}" ] && [ -x "${COMSPEC}" ] ; then
    # Detect the compiler matching the host ABI
    ocaml_configure_SAVE_DTP="${DKML_TARGET_PLATFORM:-}"
    DKML_TARGET_PLATFORM="$ocaml_configure_ABI"
    # Sets OCAML_HOST_TRIPLET that corresponds to ocaml_configure_ABI, and creates the specified script
    autodetect_compiler "$WORK"/env-with-compiler.sh
    autodetect_compiler --msvs "$WORK"/env-with-compiler.msvs
    # shellcheck disable=SC2034
    DKML_TARGET_PLATFORM=$ocaml_configure_SAVE_DTP

    # When we run OCaml's ./configure, the DKML compiler must be available
    with_environment_for_ocaml_configure() {
      tail -n -200 "$WORK"/env-with-compiler.sh >&2
      dash -x "$WORK"/env-with-compiler.sh "$@"
    }

    # Get MSVS_* aligned to the DKML compiler
    # shellcheck disable=SC1091
    . "$WORK"/env-with-compiler.msvs
    if [ -z "${MSVS_NAME}" ] ; then
      printf "%s\n" "No appropriate C compiler was found -- unable to build OCaml"
      exit 1
    fi

    # do ./configure and make using host triplet assigned in Select Host Compiler step
    windows_configure_and_define_make "$OCAML_HOST_TRIPLET" "$PREFIX" "${MSVS_PATH}" "${MSVS_LIB};" "${MSVS_INC};"
  elif [ -n "$ocaml_configure_ARCH" ] && [ -n "${COMSPEC}" ] && [ -x "${COMSPEC}" ] ; then
    ocaml_configure_PATH_PREPEND=
    ocaml_configure_LIB_PREPEND=
    ocaml_configure_INC_PREPEND=

    case "$ocaml_configure_ARCH" in
      "mingw")
        ocaml_configure_HOST=i686-w64-mingw32
      ;;
      "mingw64")
        ocaml_configure_HOST=x86_64-w64-mingw32
      ;;
      "msvc")
        ocaml_configure_HOST=i686-pc-windows
        if ! command -v ml > /dev/null ; then
          msvs_detect --arch=x86 > "$WORK"/msvs.source
          # shellcheck disable=SC1091
          . "$WORK"/msvs.source
          if [ -n "${MSVS_NAME}" ] ; then
            ocaml_configure_PATH_PREPEND="${MSVS_PATH}"
            ocaml_configure_LIB_PREPEND="${MSVS_LIB};"
            ocaml_configure_INC_PREPEND="${MSVS_INC};"
          fi
        fi
      ;;
      "msvc64")
        ocaml_configure_HOST=x86_64-pc-windows
        if ! command -v ml64 > /dev/null ; then
          msvs_detect --arch=x64 > "$WORK"/msvs.source
          # shellcheck disable=SC1091
          . "$WORK"/msvs.source
          if [ -n "${MSVS_NAME}" ] ; then
            ocaml_configure_PATH_PREPEND="${MSVS_PATH}"
            ocaml_configure_LIB_PREPEND="${MSVS_LIB};"
            ocaml_configure_INC_PREPEND="${MSVS_INC};"
          fi
        fi
      ;;
      *)
        if [ "$ocaml_configure_ARCH" != "auto" ] ; then
          printf "%s\n" "Compiler architecture $ocaml_configure_ARCH not recognised -- mingw64, mingw, msvc64, msvc (or auto)"
        fi
        if [ -n "${PROCESSOR_ARCHITEW6432:-}" ] || [ "${PROCESSOR_ARCHITECTURE:-}" = "AMD64" ] ; then
          TRY64=1
        else
          TRY64=0
        fi

        if [ ${TRY64} -eq 1 ] && command -v x86_64-w64-mingw32-gcc > /dev/null ; then
          ocaml_configure_HOST=x86_64-w64-mingw32
        elif command -v i686-w64-mingw32-gcc > /dev/null ; then
          ocaml_configure_HOST=i686-w64-mingw32
        elif [ ${TRY64} -eq 1 ] && command -v ml64 > /dev/null ; then
          ocaml_configure_HOST=x86_64-pc-windows
          ocaml_configure_PATH_PREPEND=$(bash "$DKMLDIR"/installtime/unix/private/reproducible-compile-ocaml-check_linker.sh)
        elif command -v ml > /dev/null ; then
          ocaml_configure_HOST=i686-pc-windows
          ocaml_configure_PATH_PREPEND=$(bash "$DKMLDIR"/installtime/unix/private/reproducible-compile-ocaml-check_linker.sh)
        else
          if [ ${TRY64} -eq 1 ] ; then
            ocaml_configure_HOST=x86_64-pc-windows
            ocaml_configure_HOST_ARCH=x64
          else
            ocaml_configure_HOST=i686-pc-windows
            ocaml_configure_HOST_ARCH=x86
          fi
          msvs_detect --arch=${ocaml_configure_HOST_ARCH} > "$WORK"/msvs.source
          # shellcheck disable=SC1091
          . "$WORK"/msvs.source
          if [ -z "${MSVS_NAME}" ] ; then
            printf "%s\n" "No appropriate C compiler was found -- unable to build OCaml"
            exit 1
          else
            ocaml_configure_PATH_PREPEND="${MSVS_PATH}"
            ocaml_configure_LIB_PREPEND="${MSVS_LIB};"
            ocaml_configure_INC_PREPEND="${MSVS_INC};"
          fi
        fi
      ;;
    esac
    if [ -n "${ocaml_configure_PATH_PREPEND}" ] ; then
      ocaml_configure_PATH_PREPEND="${ocaml_configure_PATH_PREPEND}:"
    fi
    # do ./configure; define make function
    windows_configure_and_define_make $ocaml_configure_HOST "$ocaml_configure_PREFIX" "$ocaml_configure_PATH_PREPEND" "$ocaml_configure_LIB_PREPEND" "$ocaml_configure_INC_PREPEND" "$ocaml_configure_EXTRA_OPTS"
  else
    # do ./configure
    # shellcheck disable=SC2086
    with_environment_for_ocaml_configure ./configure --prefix "$ocaml_configure_PREFIX" $ocaml_configure_EXTRA_OPTS
    # define make function
    ocaml_make() {
      ${MAKE:-make} "$@"
    }
  fi
}