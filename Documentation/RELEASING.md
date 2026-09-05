# Release checklist

Every public CodexStatus version must be traceable from source to download.
Complete this checklist before announcing a release.

## Repository

- Move the completed entries from `Unreleased` into a section matching the app
  version.
- Update `CFBundleShortVersionString`, increment `CFBundleVersion`, and update
  helper-reported versions.
- Keep README and feature documentation consistent with the shipped behavior.
- Commit the release on `main` and create a `v<version>` tag pointing to that
  exact commit.

## Verification

- Run the complete smoke-test suite.
- Build the release app from the tagged source.
- Verify the app bundle's version and strict code signature.
- Create the ZIP, test that it extracts successfully, and calculate SHA-256.

## GitHub Release

- Use `CodexStatus <version>` as the title and attach the verified ZIP.
- Describe user-visible features, fixes, behavior or permission changes, and
  compatibility notes under clear headings.
- Include the tests performed, installation instructions, and the exact ZIP
  SHA-256 value.
- Link to the tagged `CHANGELOG.md` entry.
- Publish only after confirming that the tag and asset upload succeeded.

## Online audit

- Read the published Release back from GitHub.
- Confirm it is neither a draft nor a prerelease unless intentionally marked.
- Confirm the tag target, asset name, byte size, and GitHub-reported digest.
- Downloading is not required when GitHub's asset digest matches the locally
  verified SHA-256, but the archive must always be tested locally before upload.
