# Direct distribution

Hasp is distributed through GitHub Releases. Keep the macOS deployment target at
26.0; using a newer SDK is not a reason to raise it.

1. Confirm repository, remote and worktree, and review the public source/history.
2. Run `python3 scripts/test-local.py` and build the complete app from this checkout
   with `python3 scripts/build-local.py --configuration Release`, selecting the
   installed Xcode with `DEVELOPER_DIR`. Record compiler, commit, version and build.
3. Copy the whole bundle into an ignored release staging directory. Sign that copy
   using the maintainer's Developer ID Application identity with hardened runtime,
   secure timestamp and `Hasp/Hasp.entitlements`. The local helper's development
   signature is not the public release signature.
4. Verify with `codesign --verify --deep --strict`. Inspect version, both Mach-O
   architectures, minimum OS and archive entries. Exclude signing profiles,
   credentials, logs and diagnostics. Create a ZIP with `ditto -c -k --keepParent`.
5. Notarize and staple before claiming a notarized release. Without notarization,
   use an explicitly labelled preview and describe Gatekeeper's rejection in the
   release notes and website. Never describe a signature check as notarization.
6. Publish the exact reviewed source tag with the ZIP, SHA256SUMS and build
   provenance. Download the published assets again; compare hashes, unpack and
   verify the signature. Update the website's pinned release and asset URL together.

The website is a separate static deployment surface. Committing it does not
publish a live website. Its dependency notices and font OFL license must remain
in the built static directory. Run its build, packaging tests and dependency audit
before publishing it.
