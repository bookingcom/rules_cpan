load("@rules_perl//perl:perl.bzl", "perl_test")

sh_test(
    name = "integration_test",
    srcs = ["integration_test.sh"],
    data = ["@lcov//:genhtml"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

perl_test(
    name = "loads-from-cpan",
    srcs = ["t/loads_from_cpan.pl"],
    deps = [
        "@cpan_deps//DateTime",
    ],
)
