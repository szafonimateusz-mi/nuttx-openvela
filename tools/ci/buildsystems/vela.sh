#!/usr/bin/env bash
# tools/ci/buildsystems/vela.sh
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.  The
# ASF licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations
# under the License.
#

# OpenVela build-system plugin for tools/testbuild.sh --buildsystem.
#
# Routes every target through OpenVela's top-level build.sh in a manifest
# workspace laid out as:
#
#   <workspace>/build.sh
#   <workspace>/nuttx        <- $nuttx
#   <workspace>/apps         <- $APPSDIR
#   <workspace>/vendor/...   <- vendor config targets
#
# Supported testlist entries:
#   board:config                    ./build.sh board:config (Make flow)
#   vendor/<...>/configs/<cfg>/     ./build.sh vendor/<...>/configs/<cfg>
#   CMake,<either form>             adds --cmake when testbuild runs with -N
#
# Blacklist entries use the testbuild grammar with the first slash of the
# target replaced by a colon:
#   -Linux,vendor:openvela/boards/vela/configs/foo/
#
# Environment:
#   VELA_REQUIRE_RUN=1  with -R, fail targets lacking an executable run file

VELA_ROOT=$(cd "$nuttx/.." && pwd)

if [ ! -x "$VELA_ROOT/build.sh" ]; then
  echo "ERROR: $VELA_ROOT/build.sh not found or not executable."
  echo "       The vela build system requires an OpenVela manifest workspace."
  exit 1
fi

VELA_EXTRA="${EXTRA_FLAGS#EXTRAFLAGS=}"
VELA_JOBS="${JOPTION#-j }"

function resolveconfig {
  if [[ "$config" == vendor/* ]]; then
    path=$VELA_ROOT/${config%/}
    if [ ! -r $path/defconfig ]; then
      echo "ERROR: no configuration found at $path"
      showusage
    fi
  else
    resolveconfig_default
  fi
}

function distclean {
  echo "  Cleaning (OpenVela)..."
  rm -rf "$VELA_ROOT/cmake_out"
  if [ -d $nuttx/.git ]; then
    git -C $nuttx clean -xfdq
  fi
  if [ -d $APPSDIR/.git ]; then
    git -C $APPSDIR clean -xfdq
  fi
  return $fail
}

function configure {
  # build.sh configures and builds in a single invocation; see build().
  return $fail
}

function build {
  echo "  Building with OpenVela build.sh..."
  local target="${config%/}"
  if [[ "$target" != vendor/* ]]; then
    target="${target/\//:}"
  fi
  local args=("$target")
  if [ ! -z ${cmake} ]; then
    args+=(--cmake)
  fi
  if [ ! -z "$VELA_EXTRA" ]; then
    args+=(-e "$VELA_EXTRA")
  fi
  if [ ! -z "$VELA_JOBS" ]; then
    args+=(-j$VELA_JOBS)
  fi
  local outdir=$ARTIFACTDIR/$(echo $config | sed "s/:/\//")
  mkdir -p $outdir
  if ! (cd "$VELA_ROOT" && ./build.sh "${args[@]}" 1>$outdir/build-stdout.log); then
    echo "  build.sh failed; last 80 lines of stdout:"
    tail -n 80 $outdir/build-stdout.log
    fail=1
  fi
  return $fail
}

function refresh {
  # OpenVela targets are not refreshed into canonical defconfig form;
  # distclean restores tree state before the next target.
  return $fail
}

function run {
  if [ ${RUN} -ne 0 ] && [ -z ${cmake} ]; then
    run_script=""
    for candidate in "$path/run.sh" "$path/run"; do
      if [ -x $candidate ]; then
        run_script=$candidate
        break
      fi
    done
    if [ ! -z "$run_script" ]; then
      echo "  Running NuttX..."
      export CURRENTCONFDIR=$(cd $path && pwd)
      export ARTIFACTCONFDIR=$ARTIFACTDIR/$(echo $config | sed "s/:/\//")
      mkdir -p $ARTIFACTCONFDIR
      if ! $run_script; then
        fail=1
      fi
    elif [ "${VELA_REQUIRE_RUN:-0}" -eq 1 ]; then
      echo "ERROR: no executable run script at $path"
      fail=1
    fi
  fi
  return $fail
}
