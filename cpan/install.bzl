_MODULE_BUILD_TEMPLATE = """\
# AUTOGENERATED BY rules_cpan

load("@rules_perl//perl:perl.bzl", "perl_library")

perl_library(
    name = "{distribution}",
    srcs = glob(["**/*"], exclude=["t/**/*", "xt/**/*"]),
    deps = [
        {deps}
    ],
    visibility = ["//visibility:public"],
)
"""

_REPO_BUILD_TEMPLATE = """\
# AUTOGENERATED BY rules_cpan

load("@rules_perl//perl:perl.bzl", "perl_library")

exports_files(["**/*"])

perl_library(
    name = "{main_target_name}",
    deps = {deps},
    visibility = ["//visibility:public"],
)
"""

def _install_impl(rctx):
    rctx = rctx  # type: repository_ctx
    lockfile = json.decode(rctx.read(rctx.attr.lock))
    for distribution, item in lockfile.items():
        rctx.download_and_extract(
            url = item["url"],
            sha256 = item["sha256"],
            stripPrefix = item["release"],
            output = distribution,
        )
        rctx.file(
            distribution + "/BUILD",
            _MODULE_BUILD_TEMPLATE.format(
                distribution = distribution,
                deps = "\n".join(["        '//{}',".format(dep.replace("::", "-")) for dep in item["dependencies"]]),
            ),
            executable = False,
        )

    rctx.file("BUILD", _REPO_BUILD_TEMPLATE.format(
        main_target_name = rctx.attr.main_target_name,
        deps = ["//" + dep for dep in lockfile.keys()],
    ), executable = False)
    rctx.file("WORKSPACE", "", executable = False)

install = repository_rule(
    attrs = {
        "lock": attr.label(allow_single_file = True, doc = "cpanfile snapshot lock file"),
        "main_target_name": attr.string(mandatory = True, doc = "The name of the top-level perl_library target. Ideally the same as the repo name."),
    },
    implementation = _install_impl,
)
