# Copyright 2017 The Bazel Authors. All rights reserved.
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
"""Rules for manipulation container images."""

load("//container:bundle.bzl", _container_bundle = "container_bundle")
load("//container:flatten.bzl", _container_flatten = "container_flatten")
load("//container:image.bzl", _container_image = "container_image", "image")
load("//container:import.bzl", _container_import = "container_import")
load("//container:load.bzl", _container_load = "container_load")
load("//container:pull.bzl", _container_pull = "container_pull")
load("//container:push.bzl", _container_push = "container_push")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
container = struct(
    image = image,
)

# Re-export imports
container_bundle = _container_bundle
container_flatten = _container_flatten
container_image = _container_image
container_import = _container_import
container_load = _container_load
container_pull = _container_pull
container_push = _container_push

# The release of the github.com/google/containerregistry to consume.
CONTAINERREGISTRY_RELEASE = "v0.0.25"

# The release of the container-structure-test repository to use.
# Updated around 1/22/2018.
STRUCTURE_TEST_COMMIT = "b97925142b1a09309537e648ade11b4af47ff7ad"

def repositories():
  """Download dependencies of container rules."""
  excludes = native.existing_rules().keys()

  if "puller" not in excludes:
    http_file(
      name = "puller",
      urls = [("https://storage.googleapis.com/containerregistry-releases/" +
             CONTAINERREGISTRY_RELEASE + "/puller.par")],
      sha256 = "d5834d24f24d7bd662074c412b29af3a78c5988d91e101ccdb240c326bd70123",
      executable = True,
    )

  if "importer" not in excludes:
    http_file(
      name = "importer",
      urls = [("https://storage.googleapis.com/containerregistry-releases/" +
             CONTAINERREGISTRY_RELEASE + "/importer.par")],
      sha256 = "b43c2504510cc069b23a205e72e96851dfa51d8ff21f8b6b5c3a78864f254ce2",
      executable = True,
    )

  if "containerregistry" not in excludes:
    git_repository(
      name = "containerregistry",
      remote = "https://github.com/google/containerregistry.git",
      tag = CONTAINERREGISTRY_RELEASE,
    )

  # TODO(mattmoor): Remove all of this (copied from google/containerregistry)
  # once transitive workspace instantiation lands.
  if "httplib2" not in excludes:
    # TODO(mattmoor): Is there a clean way to override?
    http_archive(
      name = "httplib2",
      urls = ["https://codeload.github.com/httplib2/httplib2/tar.gz/v0.10.3"],
      sha256 = "d1bee28a68cc665c451c83d315e3afdbeb5391f08971dcc91e060d5ba16986f1",
      strip_prefix = "httplib2-0.10.3/python2/httplib2/",
      type = "tar.gz",
      build_file_content = """
py_library(
   name = "httplib2",
   srcs = glob(["**/*.py"]),
   data = ["cacerts.txt"],
   visibility = ["//visibility:public"]
)""",
    )

  # Used by oauth2client
  if "six-1.9" not in excludes:
    # TODO(mattmoor): Is there a clean way to override?
    http_archive(
      name = "six-1.9",
      urls = ["https://pypi.python.org/packages/source/s/six/six-1.9.0.tar.gz"],
      sha256 = "e24052411fc4fbd1f672635537c3fc2330d9481b18c0317695b46259512c91d5",
      strip_prefix = "six-1.9.0/",
      type = "tar.gz",
      build_file_content = """
py_library(
   name = "six",
   srcs = ["six.py"],
   import = ["."],
   visibility = ["//visibility:public"],
)"""
    )

  # Used for authentication in containerregistry
  if "oauth2client" not in excludes:
    # TODO(mattmoor): Is there a clean way to override?
    http_archive(
      name = "oauth2client",
      urls = ["https://codeload.github.com/google/oauth2client/tar.gz/v4.0.0"],
      sha256 = "7230f52f7f1d4566a3f9c3aeb5ffe2ed80302843ce5605853bee1f08098ede46",
      strip_prefix = "oauth2client-4.0.0/oauth2client/",
      type = "tar.gz",
      build_file_content = """
py_library(
   name = "oauth2client",
   srcs = glob(["**/*.py"]),
   visibility = ["//visibility:public"],
   deps = [
     "@httplib2//:httplib2",
     "@six-1.9//:six",
   ]
)"""
    )

  # Used for parallel execution in containerregistry
  if "concurrent" not in excludes:
    # TODO(mattmoor): Is there a clean way to override?
    http_archive(
      name = "concurrent",
      urls = ["https://codeload.github.com/agronholm/pythonfutures/tar.gz/3.0.5"],
      sha256 = "a7086ddf3c36203da7816f7e903ce43d042831f41a9705bc6b4206c574fcb765",
      strip_prefix = "pythonfutures-3.0.5/concurrent/",
      type = "tar.gz",
      build_file_content = """
py_library(
   name = "concurrent",
   srcs = glob(["**/*.py"]),
   visibility = ["//visibility:public"]
)"""
    )

  # For packaging python tools.
  if "subpar" not in excludes:
    git_repository(
      name = "subpar",
      remote = "https://github.com/google/subpar",
      commit = "7e12cc130eb8f09c8cb02c3585a91a4043753c56",
    )

  if "structure_test" not in excludes:
    git_repository(
      name = "structure_test",
      remote = "https://github.com/GoogleCloudPlatform/container-structure-test.git",
      commit = STRUCTURE_TEST_COMMIT,
  )

  # For skylark_library.
  if "bazel_skylib" not in excludes:
    git_repository(
        name = "bazel_skylib",
        remote = "https://github.com/bazelbuild/bazel-skylib.git",
        tag = "0.2.0",
    )
