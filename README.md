# HTTP Progress Bar

[![Version Number](https://img.shields.io/github/v/release/ehennestad/http-progressbar-matlab?label=version)](https://github.com/ehennestad/http-progressbar-matlab/releases/latest)
[![MATLAB Tests](.github/badges/tests.svg)](https://github.com/ehennestad/http-progressbar-matlab/actions/workflows/test-code.yml)
[![codecov](https://codecov.io/gh/ehennestad/http-progressbar-matlab/graph/badge.svg?token=0KW9Q7178C)](https://codecov.io/gh/ehennestad/http-progressbar-matlab)
[![MATLAB Code Issues](.github/badges/code_issues.svg)](https://github.com/ehennestad/http-progressbar-matlab/security/code-scanning)
[![Run Codespell](https://github.com/ehennestad/http-progressbar-matlab/actions/workflows/run-codespell.yml/badge.svg)](https://github.com/ehennestad/http-progressbar-matlab/actions/workflows/run-codespell.yml)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://gitHub.com/ehennestad/http-progressbar-matlab/graphs/commit-activity)

Download and upload files over HTTP with a live progress display

## Description

Download files from the web and upload files to the web while showing live progress, using MATLAB's HTTP interface. Progress is shown in a waitbar, in a progress dialog attached to an app figure, or in the Command Window. It includes the transferred size, the percentage and an estimate of the remaining time.

## Requirements and installation
It is recommended to use **MATLAB R2019b** or later.
The following MathWorks products are required:
- MATLAB

Install the toolbox from MATLAB's Add-On Explorer or from [File Exchange](https://www.mathworks.com/matlabcentral/fileexchange/118460-file-downloader-uploader-with-progress-monitor). To use a clone of this repository, add `src/webprogress` to the MATLAB path.

## Getting started

The functions live in the `webprogress` namespace, so each call is qualified with `webprogress.`

```matlab
% Download a file. Progress is shown in a waitbar.
url = "https://proof.ovh.net/files/100Mb.dat";
webprogress.download(fullfile(tempdir, "100Mb.dat"), url)

% Show progress in the Command Window instead, with the file name
webprogress.download(fullfile(tempdir, "100Mb.dat"), url, ...
    "DisplayMode", "Command Window", "ShowFilename", true)

% Upload a file with a PUT request to a URL that accepts uploads,
% for example a presigned upload URL from a storage service
wasSuccess = webprogress.upload("results.mat", uploadUrl);
```

The download target is saved exactly as given, without an added extension, and replaces an existing file. Give a folder instead of a file path to save under the name the server reports.

Run `progressDialogDemo` to see the waitbar and a progress dialog in an app figure.

## Contributing
Please see the [Contributing guidelines](.github/CONTRIBUTING.md) and the [Developer notes](.github/DeveloperNotes.md)

## License

This project is available under the MIT License. See the LICENSE file for details.

## Author

Eivind Hennestad (ehennestad@gmail.com)

