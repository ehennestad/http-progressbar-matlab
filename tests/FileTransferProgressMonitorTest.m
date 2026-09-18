classdef FileTransferProgressMonitorTest < matlab.unittest.TestCase
    %FileTransferProgressMonitorTest - Tests for FileTransferProgressMonitor
    %   The tests drive the monitor directly by setting Direction and Value,
    %   as the HTTP stack does during a transfer. Progress is printed to the
    %   Command Window except in tests tagged Graphical.

    properties (TestParameter)
        unknownOptionName = struct( ...
            'misspelled', 'DisplayMdoe', ...
            'internalProperty', 'StartTime', ...
            'superclassProperty', 'Max');

        durationCase = struct( ...
            'oneSecond', struct('Value', seconds(1), 'Expected', '1 second'), ...
            'seconds', struct('Value', seconds(30), 'Expected', '30 seconds'), ...
            'minutes', struct('Value', minutes(5), 'Expected', '5 minutes'), ...
            'hours', struct('Value', hours(2), 'Expected', '2 hours'));

        intervalCase = struct( ...
            'subSecond', struct('UpdateInterval', 0.25, 'Expected', 0.25), ...
            'oneSecond', struct('UpdateInterval', 1, 'Expected', 1), ...
            'longerThanOneSecond', struct('UpdateInterval', 3600, 'Expected', 1));

        estimateCase = struct( ...
            'notMovedYet', struct('ElapsedSeconds', 60, 'PercentTransferred', 0, ...
                'Expected', 'Estimating remaining time...'), ...
            'unknownSize', struct('ElapsedSeconds', 60, 'PercentTransferred', NaN, ...
                'Expected', 'Estimating remaining time...'), ...
            'tooEarlyToEstimate', struct('ElapsedSeconds', 5, 'PercentTransferred', 25, ...
                'Expected', 'Estimating remaining time...'), ...
            'quarterTransferred', struct('ElapsedSeconds', 60, 'PercentTransferred', 25, ...
                'Expected', 'Estimated time remaining: 3 minutes...'));
    end

    properties (Constant)
        FileSizeBytes = 10 * 2^20
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            sourceFolder = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                'src', 'webprogress');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(sourceFolder));
        end
    end

    methods (Test)
        function testConstructorAppliesOptions(testCase)
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 2, ...
                'Filename', 'data.bin', 'IndentSize', 4, 'FileSizeBytes', 1000);

            testCase.verifyEqual(monitor.DisplayMode, "Command Window")
            testCase.verifyEqual(monitor.UpdateInterval, 2)
            testCase.verifyEqual(monitor.Filename, "data.bin")
            testCase.verifyEqual(monitor.IndentSize, uint8(4))
            testCase.verifyEqual(monitor.FileSizeBytes, 1000)
        end

        function testIntervalFollowsUpdateInterval(testCase, intervalCase)
            % Interval is the delay before the HTTP stack first calls the
            % monitor. A sub-second UpdateInterval only reaches the display
            % when Interval comes down with it, and a transfer shorter than
            % Interval shows no progress at all.
            monitor = webprogress.FileTransferProgressMonitor( ...
                'UpdateInterval', intervalCase.UpdateInterval);

            testCase.verifyEqual(monitor.Interval, intervalCase.Expected)
        end

        function testUnknownOptionErrors(testCase, unknownOptionName)
            testCase.verifyError( ...
                @() webprogress.FileTransferProgressMonitor(unknownOptionName, 1), ...
                'MATLAB:TooManyInputs')
        end

        function testOptionWithoutValueErrors(testCase)
            testCase.verifyError( ...
                @() webprogress.FileTransferProgressMonitor('DisplayMode'), ...
                'MATLAB:TooManyInputs')
        end

        function testActionNameIsUploadForRequest(testCase)
            monitor = webprogress.FileTransferProgressMonitor();

            monitor.Direction = matlab.net.http.MessageType.Request;

            testCase.verifyEqual(monitor.ActionName, "Upload")
        end

        function testActionNameIsDownloadForResponse(testCase)
            monitor = webprogress.FileTransferProgressMonitor();

            monitor.Direction = matlab.net.http.MessageType.Response;

            testCase.verifyEqual(monitor.ActionName, "Download")
        end

        function testPercentTransferredUsesFileSizeBytes(testCase)
            % A long update interval keeps the monitor from printing.
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 3600, ...
                'FileSizeBytes', 1000);
            monitor.Direction = matlab.net.http.MessageType.Response;

            setValues(monitor, 250)

            testCase.verifyEqual(monitor.PercentTransferred, 25, 'AbsTol', 1e-12)
        end

        function testCommandWindowPrintsEveryUpdate(testCase)
            monitor = createCommandWindowMonitor(testCase.FileSizeBytes, 'data.bin');
            megabytes = [2, 5, 9] * 2^20;

            output = captureOutput(@() setValues(monitor, megabytes));

            testCase.verifySubstring(output, 'Downloading data.bin')
            testCase.verifySubstring(output, 'Downloaded 9 MB/10 MB (90%)')
        end

        function testCommandWindowShowsDecodedFilename(testCase)
            % download passes the decoded last path segment of the URL as
            % Filename, so the name can hold characters that are percent
            % encoded in the URL. The monitor shows that name as given.
            monitor = createCommandWindowMonitor(testCase.FileSizeBytes, ...
                'my data file.json');

            output = captureOutput(@() setValues(monitor, 2 * 2^20));

            testCase.verifySubstring(output, 'Downloading my data file.json')
        end

        function testDonePrintsCompletionMessage(testCase)
            monitor = createCommandWindowMonitor(testCase.FileSizeBytes, 'data.bin');
            captureOutput(@() setValues(monitor, testCase.FileSizeBytes));

            output = captureOutput(@() monitor.done());

            testCase.verifySubstring(output, 'Downloaded 10 MB/10 MB (100%). Completed in')
        end

        function testShortenFilenameKeepsStartAndEnd(testCase)
            filename = '123456789012_middle_part_ABCDEFGHIJKL';

            shortened = webprogress.FileTransferProgressMonitor.shortenFilename(filename);

            testCase.verifyEqual(shortened, '123456789012...ABCDEFGHIJKL')
        end

        function testRemainingTimeEstimate(testCase, estimateCase)
            estimate = webprogress.FileTransferProgressMonitor.formatRemainingTimeEstimate( ...
                seconds(estimateCase.ElapsedSeconds), estimateCase.PercentTransferred);

            testCase.verifyEqual(estimate, estimateCase.Expected)
        end

        function testFormatTimeAsString(testCase, durationCase)
            durationStr = webprogress.FileTransferProgressMonitor.formatTimeAsString( ...
                durationCase.Value);

            testCase.verifyEqual(durationStr, durationCase.Expected)
        end
    end

    methods (Test, TestTags = {'Graphical'})
        function testDialogProgressBeyondFileSizeDoesNotError(testCase)
            % uiprogressdlg only accepts values from 0 to 1. A FileSizeBytes
            % that is smaller than the transfer must not abort it.
            % MatBox skips Graphical tests on GitHub Actions only from
            % R2022b, so skip here for the older releases it also tests.
            testCase.assumeNotEqual(getenv('GITHUB_ACTIONS'), 'true', ...
                'Figures cannot be created on GitHub Actions runners.')
            fig = uifigure();
            testCase.addTeardown(@() delete(fig))
            monitor = webprogress.FileTransferProgressMonitor( ...
                'Figure', fig, 'FileSizeBytes', 1000, 'UpdateInterval', 0);
            testCase.addTeardown(@() delete(monitor))
            monitor.Direction = matlab.net.http.MessageType.Response;

            testCase.verifyWarningFree(@() setValues(monitor, [500, 2500]))
        end
    end
end

function monitor = createCommandWindowMonitor(fileSizeBytes, filename)
    %createCommandWindowMonitor - Create a monitor that prints every update
    monitor = webprogress.FileTransferProgressMonitor( ...
        'DisplayMode', 'Command Window', 'UpdateInterval', 0, ...
        'Filename', filename, 'FileSizeBytes', fileSizeBytes);
    monitor.Direction = matlab.net.http.MessageType.Response;
end

function setValues(monitor, values)
    %setValues - Set Value once for each byte count, as a transfer does
    for value = values
        monitor.Value = uint64(value);
    end
end

function output = captureOutput(fcn) %#ok<INUSD> fcn is called inside evalc
    %captureOutput - Call a function and return its Command Window output
    output = evalc('fcn()');
end
