"Repository rules for importing remote apk packages"

load(":util.bzl", "util")

APK_IMPORT_TMPL = """\
# Generated by apk_import. DO NOT EDIT
filegroup(
    name = "all", 
    srcs = glob(["**/*.tar.gz", "**/*.apk"]),
    visibility = ["//visibility:public"]
)
"""

def _range(url, range):
    return "{}#_apk_range_{}".format(url, range.replace("=", "_"))

def _check_initial_setup(rctx):
    output = rctx.path(".rangecheck/output")
    rctx.download(
        url = [_range(rctx.attr.url, "bytes=0-0")],
        output = output,
    )
    r = rctx.execute(["wc", "-c", output])

    if r.return_code != 0:
        fail("initial setup check failed ({}) stderr: {}\n stdout: {}".format(r.statuscode, r.stderr, r.stdout))

    bytes = r.stdout.lstrip(" ").split(" ")

    if bytes[0] != "1":
        fail("""

‼️ We encountered an issue with your current configuration that prevents partial package fetching during downloads. 

This may indicate either a misconfiguration or that the initial setup hasn't been performed correctly.
To resolve this issue and enable partial package fetching, please follow the step-by-step instructions in our documentation. 

📚 Documentation: https://github.com/chainguard-dev/rules_apko/blob/main/docs/initial-setup.md

""".format(bytes[0]))

def _apk_import_impl(rctx):
    repo = util.repo_url(rctx.attr.url, rctx.attr.architecture)
    repo_escaped = util.url_escape(repo)

    output = "{}/{}/{}-{}".format(repo_escaped, rctx.attr.architecture, rctx.attr.package_name, rctx.attr.version)

    control_sha256 = util.normalize_sri(rctx, rctx.attr.control_checksum)
    data_sha256 = util.normalize_sri(rctx, rctx.attr.data_checksum)

    sig_output = "{}/{}.sig.tar.gz".format(output, control_sha256)
    control_output = "{}/{}.ctl.tar.gz".format(output, control_sha256)
    data_output = "{}/{}.dat.tar.gz".format(output, data_sha256)
    apk_output = "{}/{}/{}-{}.apk".format(repo_escaped, rctx.attr.architecture, rctx.attr.package_name, rctx.attr.version)

    _check_initial_setup(rctx)

    rctx.download(
        url = [_range(rctx.attr.url, rctx.attr.signature_range)],
        output = sig_output,
        # TODO: signatures does not have stable checksums. find a way to fail gracefully.
        integrity = rctx.attr.signature_checksum,
    )
    rctx.download(
        url = [_range(rctx.attr.url, rctx.attr.control_range)],
        output = control_output,
        integrity = rctx.attr.control_checksum,
    )
    rctx.download(
        url = [_range(rctx.attr.url, rctx.attr.data_range)],
        output = data_output,
        integrity = rctx.attr.data_checksum,
    )

    util.concatenate_gzip_segments(
        rctx,
        output = apk_output,
        signature = sig_output,
        control = control_output,
        data = data_output,
    )
    rctx.file("BUILD.bazel", APK_IMPORT_TMPL)

apk_import = repository_rule(
    implementation = _apk_import_impl,
    attrs = {
        "package_name": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "architecture": attr.string(mandatory = True),
        "url": attr.string(mandatory = True),
        "signature_range": attr.string(mandatory = True),
        "signature_checksum": attr.string(mandatory = True),
        "control_range": attr.string(mandatory = True),
        "control_checksum": attr.string(mandatory = True),
        "data_range": attr.string(mandatory = True),
        "data_checksum": attr.string(mandatory = True),
    },
)

APK_REPOSITORY_TMPL = """\
# Generated by apk_repository. DO NOT EDIT
filegroup(
    name = "index", 
    srcs = glob(["**/APKINDEX/*.tar.gz"]),
    visibility = ["//visibility:public"]
)
"""

def _apk_repository_impl(rctx):
    repo = util.repo_url(rctx.attr.url, rctx.attr.architecture)
    repo_escaped = util.url_escape(repo)
    rctx.download(
        url = [rctx.attr.url],
        output = "{}/{}/APKINDEX/latest.tar.gz".format(repo_escaped, rctx.attr.architecture),
    )
    rctx.file("BUILD.bazel", APK_REPOSITORY_TMPL)

apk_repository = repository_rule(
    implementation = _apk_repository_impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "architecture": attr.string(mandatory = True),
    },
)

APK_KEYRING_TMPL = """\
# Generated by apk_import. DO NOT EDIT
filegroup(
    name = "keyring", 
    srcs = glob(["**/*.pub"]),
    visibility = ["//visibility:public"]
)
"""

def _apk_keyring_impl(rctx):
    scheme = "https"
    url = rctx.attr.url
    if url.startswith("http://"):
        url = url[len("http://"):]
        scheme = "http"
    if url.startswith("https://"):
        url = url[len("https://"):]

    # split at first slash once to get base url and the path
    url_split = url.split("/", 1)

    path = url_split[1]
    repo = util.url_escape("{}://{}/".format(scheme, url_split[0]))

    rctx.download(
        url = [rctx.attr.url],
        output = "{}/{}".format(repo, path),
    )
    rctx.file("BUILD.bazel", APK_KEYRING_TMPL)

apk_keyring = repository_rule(
    implementation = _apk_keyring_impl,
    attrs = {
        "url": attr.string(mandatory = True),
    },
)
