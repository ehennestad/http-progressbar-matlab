# Developer Notes

## Repository layout

| Path | Contents |
|---|---|
| `src/webprogress` | Toolbox code. MatBox packages this folder and puts it and its subfolders, except namespace and `private` folders, on the installed toolbox's path. |
| `src/webprogress/examples/progressDialogDemo.m` | Plain-text live script used as the toolbox's getting started guide. It opens as a live script in MATLAB R2025a or later. |
| `tests` | Unit tests. CI runs them on pull requests to `main`. |
| `tools/MLToolboxInfo.json` | Toolbox metadata that MatBox reads when it packages the toolbox. |
| `tools/+webprogresstools` | Development helpers. |

## Running the tests

Run the tests the way CI does:

```matlab
addpath("tools")
webprogresstools.installMatBox()  % Once, if MatBox is not installed
matbox.tasks.testToolbox(webprogresstools.projectdir(), "CreateBadge", false)
```

MatBox writes the test and coverage reports to `docs/reports`, which git ignores. Without `"CreateBadge", false`, it also updates the badge images in `.github/badges`.

## Code style

Follow the [MATLAB Coding Guidelines](https://github.com/mathworks/MATLAB-Coding-Guidelines) and keep the code free of Code Analyzer warnings. CI reports Code Analyzer issues on pull requests.

## Pull requests

CI commits regenerated badge images in `.github/badges` to the branch of a pull request. Pull that commit before you push more commits to the branch.

## Releases

Run the **Prepare toolbox release** workflow with a version number in major.minor.patch format, or push a tag such as `v1.2.1`. The workflow tests the toolbox on MATLAB releases chosen from the release range in `tools/MLToolboxInfo.json`, packages it with MatBox, and creates a draft GitHub release. It needs a `DEPLOY_KEY` repository secret that holds an SSH deploy key with write access.

Keep `Identifier` in `tools/MLToolboxInfo.json` unchanged. It matches the File Exchange submission, so installing a new release replaces an installed earlier version.
