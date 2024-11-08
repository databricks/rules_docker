#!/bin/bash
#
# Copyright 2015 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

# This is a generated file that loads all docker layers built by "docker_build".

function guess_runfiles() {
    pushd ${BASH_SOURCE[0]}.runfiles > /dev/null 2>&1
    pwd
    popd > /dev/null 2>&1
}

RUNFILES="${PYTHON_RUNFILES:-$(guess_runfiles)}"

DOCKER="${DOCKER:-docker}"

# Create temporary files in which to record things to clean up.
TEMP_FILES="$(mktemp -t 2>/dev/null || mktemp -t 'rules_docker_files')"
TEMP_IMAGES="$(mktemp -t 2>/dev/null || mktemp -t 'rules_docker_images')"
function cleanup() {
  cat "${TEMP_FILES}" | xargs rm -rf> /dev/null 2>&1 || true
  cat "${TEMP_IMAGES}" | xargs "${DOCKER}" rmi > /dev/null 2>&1 || true

  rm -rf "${TEMP_FILES}"
  rm -rf "${TEMP_IMAGES}"
}
trap cleanup EXIT


function load_legacy() {
  local tarball="${RUNFILES}/$1"

  # docker load has elision of preloaded layers built in.
  echo "Loading legacy tarball base $1..."
  "${DOCKER}" load -i "${tarball}"
}

function join_by() {
  local IFS="$1"
  shift
  echo "$*"
}

function import_config() {
  local TAG="$1"
  shift 1

  local registry_output="$(mktemp)"
  echo "${registry_output}" >> "${TEMP_FILES}"
  "${RUNFILES}/%{registry_tool}" -- "${registry_output}" "image" "$@" &
  local registry_pid=$!

  # If we can do that, symlinking the layer diff blobs into the containerd
  # content dir is a way to skip downloading them, and then keeping the
  # downloaded copy. After creating the snapshot of the image, we don't
  # need the layer blobs anymore, but there's no way to prune the content
  # store. As they aren't really needed, it's OK if the symlinks
  # eventually dangle.
  if [[ -w "/var/lib/containerd/io.containerd.content.v1.content/blobs/sha256" ]]; then
    shift 1
    while test $# -gt 0
    do
      local diff_id="$(cat "${RUNFILES}/$1")"
      local layer="${RUNFILES}/$2"
      local layer_in_content_store="/var/lib/containerd/io.containerd.content.v1.content/blobs/sha256/${diff_id}"
      if [[ ! -e "${layer_in_content_store}" ]]; then
        if [[ -L "${layer_in_content_store}" ]]; then
          rm "${layer_in_content_store}"
        fi
        ln -s "$(readlink -f "${layer}")" "${layer_in_content_store}"
      fi
      shift 2
    done
  fi

  local ref=$(tail -f "${registry_output}" | head -1)
  "${DOCKER}" pull "${ref}"
  kill "${registry_pid}"

  "${DOCKER}" tag "${ref}" "${TAG}"
  "${DOCKER}" rmi "${ref}"
}

function read_variables() {
  local file="${RUNFILES}/$1"
  local new_file="$(mktemp -t 2>/dev/null || mktemp -t 'rules_docker_new')"
  echo "${new_file}" >> "${TEMP_FILES}"

  # Rewrite the file from Bazel for the form FOO=...
  # to a form suitable for sourcing into bash to expose
  # these variables as substitutions in the tag statements.
  sed -E "s/^([^ ]+) (.*)\$/export \\1='\\2'/g" < ${file} > ${new_file}
  source ${new_file}
}

# Statements initializing stamp variables.
%{stamp_statements}

# List of 'import_config' statements for all images.
# This generated and injected by docker_*.
%{load_statements}

# An optional "docker run" statement for invoking a loaded container.
# This is not executed if the single argument --norun is passed.
if [ "a$*" != "a--norun" ]; then
  # This generated and injected by docker_*.
  %{run_statements}
  # Empty if blocks can be problematic.
  echo > /dev/null
fi
