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

        % 0.01 is the cap the monitor puts on ProgressMonitor.Interval.
        intervalCase = struct( ...
            'belowTheCap', struct('UpdateInterval', 0.002, 'Expected', 0.002), ...
            'subSecond', struct('UpdateInterval', 0.25, 'Expected', 0.01), ...
            'oneSecond', struct('UpdateInterval', 1, 'Expected', 0.01), ...
            'longerThanOneSecond', struct('UpdateInterval', 3600, 'Expected', 0.01));

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

        function testIntervalIsCappedBelowUpdateInterval(testCase, intervalCase)
            % Interval is the delay before the HTTP stack first calls the
            % monitor, and the stack skips that call when the transfer
            % finishes first. It therefore has to stay well below
            % UpdateInterval, which only throttles the display.
            monitor = webprogress.FileTransferProgressMonitor( ...
                'UpdateInterval', intervalCase.UpdateInterval);

            testCase.verifyEqual(monitor.Interval, intervalCase.Expected)
        end

        function testFirstProgressIsShownBeforeUpdateInterval(testCase)
            % A transfer that finishes within one UpdateInterval must
            % still report its progress, so the first update does not wait
            % for the interval to pass.
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 3600, ...
                'Filename', 'data.bin', 'FileSizeBytes', testCase.FileSizeBytes);
            monitor.Direction = matlab.net.http.MessageType.Response;

            output = captureOutput(@() setValues(monitor, 5 * 2^20));

            testCase.verifySubstring(output, 'Downloading data.bin')
            testCase.verifySubstring(output, 'Downloaded 5 MB/10 MB (50%)')
        end

        function testLaterProgressWaitsForUpdateInterval(testCase)
            % Only the first update bypasses UpdateInterval. The ones that
            % follow are throttled, so a long interval keeps them quiet.
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 3600, ...
                'FileSizeBytes', testCase.FileSizeBytes);
            monitor.Direction = matlab.net.http.MessageType.Response;
            captureOutput(@() setValues(monitor, 2 * 2^20));

            output = captureOutput(@() setValues(monitor, [5, 9] * 2^20));

            testCase.verifyEmpty(output)
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
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 3600, ...
                'FileSizeBytes', 1000);
            monitor.Direction = matlab.net.http.MessageType.Response;

            % The monitor displays the first progress it receives whatever
            % the update interval, so capture it rather than print it.
            captureOutput(@() setValues(monitor, 250));

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

        function testUnknownSizeIsNotReportedAsNaN(testCase)
            % Neither the message nor the caller reports a size here, so
            % the total and the percentage are both unknown.
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0);
            monitor.Direction = matlab.net.http.MessageType.Response;
            captureOutput(@() setValues(monitor, 3 * 2^20));

            output = captureOutput(@() monitor.done());

            testCase.verifySubstring(output, 'Downloaded 3 MB. Completed in')
            testCase.verifyThat(output, ...
                ~matlab.unittest.constraints.ContainsSubstring('NaN'))
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

        function testCancelKeepsTheWaitbarClosed(testCase)
            % The HTTP stack keeps reporting byte counts for a while after
            % a cancellation, because it aborts the transfer at its next
            % opportunity rather than at once. None of those reports may
            % reopen the waitbar the user has just dismissed.
            testCase.assumeNotEqual(getenv('GITHUB_ACTIONS'), 'true', ...
                'Figures cannot be created on GitHub Actions runners.')
            delete(findWaitbars())
            testCase.addTeardown(@() delete(findWaitbars()))
            monitor = webprogress.FileTransferProgressMonitor( ...
                'FileSizeBytes', 1000, 'UpdateInterval', 0);
            testCase.addTeardown(@() delete(monitor))
            monitor.Direction = matlab.net.http.MessageType.Response;
            setValues(monitor, 100)
            testCase.assumeNumElements(findWaitbars(), 1)

            pressCancel(findWaitbars())
            setValues(monitor, [200, 300])

            testCase.verifyEmpty(findWaitbars())
        end
    end
end

function bars = findWaitbars()
    %findWaitbars - Return the open waitbar figures
    bars = findall(0, 'Type', 'figure', 'Tag', 'TMWWaitbar');
end

function pressCancel(waitbarFigure)
    %pressCancel - Press the waitbar's Cancel button as a user would
    button = findall(waitbarFigure, 'Style', 'pushbutton');
    callback = button(1).Callback;
    callback(button(1), [])
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
