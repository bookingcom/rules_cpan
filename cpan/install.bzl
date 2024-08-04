_MODULE_BUILD_TEMPLATE = """\
# AUTOGENERATED BY rules_cpan

load("@rules_perl//perl:perl.bzl", "perl_library")

perl_library(
    name = "{distribution}",
    srcs = glob(["lib/**/*"]),
    visibility = ["//visibility:public"],
)
"""

_REPO_BUILD_TEMPLATE = """\
# AUTOGENERATED BY rules_cpan

load("@rules_perl//perl:perl.bzl", "perl_library")

exports_files(["**/*"])

perl_library(
    name = "{repo}",
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
        rctx.file(distribution + "/BUILD", _MODULE_BUILD_TEMPLATE.format(distribution = distribution), executable = False)

    rctx.file("BUILD", _REPO_BUILD_TEMPLATE.format(
        repo = rctx.name.split("~")[-1],
        deps = ["//" + dep for dep in lockfile.keys()],
    ), executable = False)
    rctx.file("WORKSPACE", "", executable = False)

install = repository_rule(
    attrs = {
        "lock": attr.label(allow_single_file = True, doc = "cpanfile snapshot lock file"),
    },
    implementation = _install_impl,
)
