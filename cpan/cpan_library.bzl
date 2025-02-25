load("@rules_cc//cc:defs.bzl", "CcInfo")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")
load("@rules_perl//perl:perl.bzl", "PerlLibrary")

def _include_paths(ctx):
    """Calculate the PERL5LIB paths for a perl_library rule's includes."""
    workspace_name = ctx.label.workspace_name
    if workspace_name:
        workspace_root = "../" + workspace_name
    else:
        workspace_root = ""
    package_root = (workspace_root + "/" + ctx.label.package).strip("/") or "."
    include_paths = [
        "/".join([package_root, "lib", "perl5", "x86_64-linux"]),
        "/".join([package_root, "lib", "perl5"]),
    ]
    for dep in ctx.attr.deps:
        include_paths.extend(dep[PerlLibrary].includes)
    include_paths = depset(direct = include_paths).to_list()
    return include_paths

def _transitive_srcs(deps):
    return struct(
        srcs = [
            d[PerlLibrary].transitive_perl_sources
            for d in deps
            if PerlLibrary in d
        ],
        files = [
            d[DefaultInfo].default_runfiles.files
            for d in deps
        ],
    )

def _perl_cpan_library_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    perl_toolchain = ctx.toolchains["@rules_perl//perl:toolchain_type"].perl_runtime

    build_dir = ctx.actions.declare_directory("lib")

    env = {
        "AR": cc_toolchain.ar_executable,
        "CC": cc_toolchain.compiler_executable,
        "LD": cc_toolchain.ld_executable,
        "NM": cc_toolchain.nm_executable,
        "OBJCOPY": cc_toolchain.objcopy_executable,
        "OBJDUMP": cc_toolchain.objdump_executable,
        "CPP": cc_toolchain.preprocessor_executable,
        "STRIP": cc_toolchain.strip_executable,
        "SYSROOT": cc_toolchain.sysroot,
    }

    for key in env.keys():
        if not env[key]:
            env[key] = ""

    make = ctx.toolchains["@rules_foreign_cc//toolchains:make_toolchain"].data

    env.update(make.env)

    tools = [
        cc_toolchain.all_files,
        make.target.files,
    ]

    perl5lib = _include_paths(ctx)
    tools.extend(_transitive_srcs(ctx.attr.deps).files)

    if ctx.attr.build_deps:
        perl_sources = _transitive_srcs(ctx.attr.build_deps).files
        tools.extend(perl_sources)

        for dep in ctx.attr.build_deps:
            perl5lib.extend(dep[PerlLibrary].includes)

    perl5lib = [
        x.replace("../", "/".join([ctx.var["BINDIR"], "external/"]))
        for x in perl5lib
        if x
    ]

    env["EXTRA_PERL5LIB"] = ":".join([x for x in sorted(set(perl5lib))])

    ctx.actions.run(
        outputs = [build_dir],
        inputs = ctx.files.srcs +
                 perl_toolchain.runtime +
                 ctx.files.build_deps +
                 [ctx.file.makefile_pl],
        arguments = [
            ctx.file.makefile_pl.path,
            build_dir.path,
        ],
        executable = ctx.executable._build_with_make,
        tools = tools,
        env = env,
    )

    return [
        DefaultInfo(
            files = depset([build_dir]),
            runfiles = ctx.runfiles(
                files = [build_dir],
                transitive_files = depset(transitive = _transitive_srcs(ctx.attr.deps).files),
            ),
        ),
        PerlLibrary(
            transitive_perl_sources = depset([build_dir]),
            includes = _include_paths(ctx),
        ),
    ]

perl_cpan_library = rule(
    implementation = _perl_cpan_library_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "makefile_pl": attr.label(allow_single_file = [".PL"]),
        "cc_deps": attr.label_list(providers = [CcInfo]),
        "deps": attr.label_list(providers = [PerlLibrary]),
        "build_deps": attr.label_list(providers = [PerlLibrary]),
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
        "_build_with_make": attr.label(
            default = Label("@rules_cpan//cpan:build-with-make"),
            cfg = "exec",
            executable = True,
        ),
    },
    toolchains = [
        "@rules_perl//perl:toolchain_type",
        "@bazel_tools//tools/cpp:toolchain_type",
        "@rules_foreign_cc//toolchains:make_toolchain",
    ],
)
