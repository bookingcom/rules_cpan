load("@aspect_bazel_lib//lib:run_binary.bzl", "run_binary")
load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library")
load("@rules_perl//perl:perl.bzl", "perl_binary")

perl_binary(
    name = "dump-core-modules",
    srcs = ["dump-core-modules.pl"],
)

run_binary(
    name = "core-modules",
    outs = ["core-modules.json"],
    args = ["$(location core-modules.json)"],
    tool = ":dump-core-modules",
)

py_binary(
    name = "snapshot",
    srcs = ["snapshot.py"],
    data = [
        ":core-modules.json",
    ],
    env = {
        "CORE_MODULES": "../$(rlocationpath core-modules.json)",
    },
    visibility = ["//:__subpackages__"],
    deps = [
        "@pip//filetype",
        "@pip//pyyaml",
        "@pip//requests",
        "@pip//xdg_base_dirs",
    ],
)

py_library(
    name = "snapshot_library",
    srcs = ["snapshot.py"],
    visibility = ["//:__subpackages__"],
    deps = [
        "@pip//filetype",
        "@pip//pyyaml",
        "@pip//requests",
        "@pip//xdg_base_dirs",
    ],
)
