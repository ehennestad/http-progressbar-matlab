%[text] # File Transfer Progress Dialog Demo
%[text] This script demonstrates the two dialog-based progress displays of `downloadFile`:
%[text] - A standard MATLAB waitbar.
%[text] - A `uiprogressdlg` parented to a `uifigure`. \
%[text] Each section downloads a 100 MB [test file that OVHcloud publishes for download speed tests](https://proof.ovh.net/files/). On a slow connection, use the 10 MB file, `10Mb.dat`, instead.
demoUrl = 'https://proof.ovh.net/files/100Mb.dat';
standardWaitbarFile = fullfile(tempdir, 'filedownload_standard_waitbar_demo.dat');
uiProgressDialogFile = fullfile(tempdir, 'filedownload_uiprogressdlg_demo.dat');
%%
%[text] ## Standard Waitbar
%[text] Without a `Figure` argument, `downloadFile` uses a standard waitbar dialog.
deleteIfExists(standardWaitbarFile)
downloadFile(standardWaitbarFile, demoUrl, ...
    'DisplayMode', 'Dialog Box', ...
    'UpdateInterval', 1, ...
    'ShowFilename', true);
%%
%[text] ## Progress Dialog in a UIFigure
%[text] Passing a `uifigure` through the `Figure` argument makes `downloadFile` use a `uiprogressdlg` instead of a standard waitbar.
fig = uifigure('Name', 'File Transfer Progress Demo');
uilabel(fig, ...
    'Text', 'Progress is shown with uiprogressdlg attached to this uifigure.', ...
    'Position', [24, fig.Position(4)/2, 372, 30]);
drawnow
deleteIfExists(uiProgressDialogFile)
downloadFile(uiProgressDialogFile, demoUrl, ...
    'DisplayMode', 'Dialog Box', ...
    'UpdateInterval', 1, ...
    'ShowFilename', true, ...
    'Figure', fig);
%%
%[text] ## Optional Cleanup
%[text] Run this section when you no longer need the downloaded demo files.
deleteIfExists(standardWaitbarFile)
deleteIfExists(uiProgressDialogFile)
if exist('fig', 'var') && isvalid(fig)
    close(fig)
end
%%
%[text] ## Local Functions
function deleteIfExists(filename)
    if isfile(filename)
        delete(filename)
    end
end

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
