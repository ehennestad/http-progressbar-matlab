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

Users or developers who clone the repository using git can use [MatBox](https://github.com/ehennestad/MatBox) to quickly install this project's [requirements](./requirements.txt) (if any):

```matlab
webprogresstools.installMatBox() % If MatBox is not installed
matbox.installRequirements(path/to/toolboxRootDir)
```

## Getting started

```matlab
< add some code examples here >
```

## Contributing
Please see the [Contributing guidelines](.github/CONTRIBUTING.md) and the [Developer notes](.github/DeveloperNotes.md)

## License

This project is available under the MIT License. See the LICENSE file for details.

## Author

Eivind Hennestad (ehennestad@gmail.com)

