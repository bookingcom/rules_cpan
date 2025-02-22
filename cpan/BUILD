load("@rules_perl//perl:perl.bzl", "perl_binary")
load(":install.bzl", "perl_toolchain_path")

perl_toolchain_path(
    name = "perl_toolchain_path",
)

perl_binary(
    name = "run-makefile-pl",
    srcs = ["run-makefile.pl", ":perl_toolchain_path"],
    main = "run-makefile.pl",
    visibility = ["//visibility:public"]
)
