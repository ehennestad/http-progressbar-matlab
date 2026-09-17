% [text] # File Transfer Progress Dialog Demo
% [text] This script demonstrates the two dialog-based progress displays:
% [text] - A standard MATLAB waitbar.
% [text] - A uiprogressdlg parented to a uifigure. \
demoUrl = 'https://allen-brain-observatory.s3.us-west-2.amazonaws.com/visual-coding-2p/cell_specimens.json';

standardWaitbarFile = fullfile(tempdir, 'filedownload_standard_waitbar_demo.json');
uiProgressDialogFile = fullfile(tempdir, 'filedownload_uiprogressdlg_demo.json');
%%
% [text] ## Standard Waitbar
% [text] Without a Figure argument, downloadFile uses a standard waitbar dialog.
deleteIfExists(standardWaitbarFile)

downloadFile(standardWaitbarFile, demoUrl, ...
    'DisplayMode', 'Dialog Box', ...
    'UpdateInterval', 1, ...
    'ShowFilename', true);
%%
% [text] ## Progress Dialog In A UIFigure
% [text] Passing a uifigure through the Figure argument makes downloadFile use a uiprogressdlg instead of a standard waitbar.
fig = uifigure( ...
    'Name', 'File Transfer Progress Demo');

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
% [text] ## Optional Cleanup
% [text] Run this section when you no longer need the downloaded demo files.
deleteIfExists(standardWaitbarFile)
deleteIfExists(uiProgressDialogFile)

if exist('fig', 'var') && isvalid(fig)
    close(fig)
end
%%
% [text] ## Local Functions
function deleteIfExists(filename)
    if isfile(filename)
        delete(filename)
    end
end

% [appendix]{"version":"1.0"}
% ---
% [metadata:view]
%   data: {"layout":"inline","rightPanelPercent":5.5}
% ---
