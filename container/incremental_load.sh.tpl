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

  # Save the arguments to forward to our loader tool
  local config_and_layers=("$@")

  # This is an optimization that only affects systems using containerd storage, namely RBE. 
  # In this case, when we 'docker pull', the docker client will ask the snapshotter what to do.
  # The snapshotter will either say:
  #   1. I don't have this, go ahead and pull it; OR
  #   2. I already have it, you don't need to pull anything.
  # In case of (1.), we will store this into a place called 'content store'.
  # When using sysbox docker-in-docker, this 'content store' is local to every daemon.
  # Once we need to create a container, we will copy the image from the 'content store' into
  # the snapshotter, which is shared across all daemons.
  # In the worst case, if many actions try to pull the same image on a cold snapshotter,
  # we would end up with one copy of the image in every daemon 'content store'.
  # The trick: instead of actually copying the image to the content store, we just drop a symlink
  # from the action inputs into the 'content store'. The docker client is smart enough to pull only
  # what's missing on their content stores.
  # To recap:
  #   1. We symlink the image layers into the local daemon 'content store'.
  #   2. We docker pull from our local registry.
  #   3. The docker client will ask the snapshotter whether it needs to pull the image or not.
  #   4. If the snapshotter says yes, we will start the pull operation.
  #   5. The pull operation is a no-op due to (1.), i.e. all the layers are already present.
  #   6. When we create a container, we load the image into the snapshotter.
  #   7. The snapshotter will dedupe images in case of race conditions.
  # Once loaded in the snapshotter, we don't care about the content store anymore. So it's fine
  # if those symlinks dangle.
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

  # Load and pull the image from the local registry
  local ref=$("${RUNFILES}/%{loader_tool}" "${DOCKER}" "${config_and_layers[@]}")

  # Prints to keep compatibility on other scripts parsing this output
  # since 'docker load' used to print the sha
  local image_id=$("${DOCKER}" inspect --format "{{ .Id }}" "${ref}" | awk -F'sha256:' '{print $2}')
  echo sha256:${image_id}

  echo "Tagging ${image_id} as ${TAG}"
  "${DOCKER}" tag "${ref}" "${TAG}"

  # Clean up the temporary tag created by docker pull
  # This DOES NOT delete the image, just the tag.
  # By default, docker pull creates a tag based on the reference you pulled from.
  "${DOCKER}" rmi "${ref}" >&2
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
