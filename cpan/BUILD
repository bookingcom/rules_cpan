load("@rules_perl//perl:perl.bzl", "perl_binary")
load(":install.bzl", "perl_toolchain_path")

perl_toolchain_path(
    name = "perl_toolchain_path",
)

perl_binary(
    name = "build-with-make",
    srcs = ["build-with-make.pl"],
    visibility = ["//visibility:public"],
)
