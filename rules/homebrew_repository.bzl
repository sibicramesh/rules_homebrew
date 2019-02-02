load("@bazel_tools//tools/build_defs/repo:utils.bzl", "patch")

BUILD_FILE_CONTENT = '''
#filegroup(
#    name = "brew",
#    srcs = ["bin/brew"],
#    visibility = ["//visibility:public"],
#)

#filegroup(
#    name = "allbinaries",
#    srcs = glob(["bin/*"], exclude=["bin/brew"]),
#    visibility = ["//visibility:public"],
#)

filegroup(
    name = "library",
    srcs = glob(["Library/**"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "cellar",
    srcs = ["Cellar"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "allfiles",
    srcs = glob(
        ["*", "**/*"],
        exclude=["**/*:*", "**/* *"],
    ),
    visibility = ["//visibility:public"],
)

'''

sh_binary_template = '''
sh_binary(
    name = "{name}",
    srcs = ["bin/{name}"],
    visibility = ["//visibility:public"],
)
'''

def generate_build_file(ctx):
    binaries = ''
    for binary in _installed_binaries(ctx):
        binaries += sh_binary_template.format(
            name = binary,
        )

    return BUILD_FILE_CONTENT + binaries


def _homebrew_repository_impl(ctx):
    """Implementation of the homebrew_repository rule."""

    # network access
    tag = ctx.attr.homebrew_tag
    url = "https://github.com/Homebrew/brew/archive/%s.tar.gz" % ctx.attr.homebrew_tag
    url_sha = ctx.attr.homebrew_sha256

    all_brew_urls = []
    if ctx.attr.brew_urls:
        all_brew_urls = ctx.attr.brew_urls
    all_brew_urls = [url] + all_brew_urls

    ctx.download_and_extract(
        all_brew_urls,
        "",
        url_sha,
        "",
        "brew-%s" % tag,
    )

    homebrew_core_commit = ctx.attr.homebrew_core_commit
    homebrew_core_url = "https://codeload.github.com/Homebrew/homebrew-core/zip/%s" % ctx.attr.homebrew_core_commit
    homebrew_core_sha = ctx.attr.homebrew_core_sha256

    all_homebrew_core_urls = []
    if ctx.attr.homebrew_core_urls:
        all_homebrew_core_urls = ctx.attr.homebrew_core_urls
    all_homebrew_core_urls = [homebrew_core_url] + all_homebrew_core_urls

    ctx.download_and_extract(
        all_homebrew_core_urls,
        "Library/Taps/homebrew/homebrew-core",
        homebrew_core_sha,
        "zip",
        "homebrew-core-%s" % homebrew_core_commit,
    )
    patch(ctx)

    ctx.execute(["mkdir","cache"])

    ctx.template("brew-wrapper.sh", ctx.attr.brew_wrappper_template)

    extra_args = []
    if ctx.attr.verbose:
        extra_args += ["--verbose"]

    cmd = [
        "./brew-wrapper.sh",
        "install",
        #"--no-sandbox",
        # TODO(tmc): "--ignore-dependencies", # force our hand
    ] + ctx.attr.packages
    result = ctx.execute(cmd, quiet = ctx.attr.verbose == False)
    if ctx.attr.verbose:
        print("[rules_homebrew]", result.return_code, result.stdout, result.stderr)
    if result.return_code != 0:
        fail("[brew_packges] " + result.stderr)

    build_file_content = generate_build_file(ctx)
    ctx.file("BUILD", build_file_content)
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")\n".format(name = ctx.name))

    # TODO(tmc): move this to use update_attrs(ctx.attr, _homebrew_repository_attrs.keys(), {"brew_sha256": brew_download_info.sha256, "homebrew_core_sha256": homebrew_core_download_info.sha256})

def _formula_version(ctx, formula):
    r = ctx.execute(["./brew-wrapper.sh", "ls", "--versions", formula])
    if ctx.attr.verbose:
        print("[rules_homebrew]", r.return_code, r.stdout, r.stderr)
    return r.stdout.strip().split(" ")[-1]

def _installed_binaries(ctx):
    r = ctx.execute(["ls", "bin"])
    return [x for x in r.stdout.splitlines() if x != "brew"]

def _formula_binaries(ctx, formula):
    r = ctx.execute(["./brew-wrapper.sh", "list", formula])
    if ctx.attr.verbose:
        print("[rules_homebrew]", r.return_code, r.stdout, r.stderr)
    binaries = [x.split("/")[-1] for x in r.stdout.splitlines() if "/bin/" in x]
    unique = {}
    for b in binaries:
        unique[b] = True
    return unique.keys()

def _formula_is_installed(ctx, formula):
    r = ctx.execute(["./brew-wrapper.sh", "ls", "--versions", formula])
    if ctx.attr.verbose:
        print("[rules_homebrew]", r.return_code, r.stdout, r.stderr)
    return r.return_code == 0

def _filter_installed_packages(ctx, formulas):
    return [f for f in formulas if not _formula_is_installed(ctx, f)]
_homebrew_repository_attrs = {
    "homebrew_tag": attr.string(default = "2.0.0"),
    "homebrew_sha256": attr.string(default = "154db4fc7cd3853e3e7939462c546db76f2e132c5cb2133490bf02abfcf531f5"),
    "homebrew_core_commit": attr.string(default = "98017e7ff3e43e394280946eda8003479e1e7be7"),
    "homebrew_core_sha256": attr.string(default = "ad18d82d39ce90d7b8ac3f0ddd4503d56505c83d3b23160365380a4655eee0d1"),
    "brew_urls": attr.string_list(),
    "homebrew_core_urls": attr.string_list(),
    "patches": attr.label_list(default = []),
    "patch_tool": attr.string(default = "patch"),
    "patch_args": attr.string_list(default = ["-p0"]),
    "patch_cmds": attr.string_list(default = []),
    "workspace_file": attr.label(allow_single_file = True),
    "workspace_file_content": attr.string(),

    "packages": attr.string_list(mandatory = True),
    "brew_wrappper_template": attr.label(default = "//scripts:brew-wrapper.sh"),
    "verbose": attr.bool(),
}


homebrew_repository = repository_rule(
    implementation = _homebrew_repository_impl,
    attrs = _homebrew_repository_attrs,
)

