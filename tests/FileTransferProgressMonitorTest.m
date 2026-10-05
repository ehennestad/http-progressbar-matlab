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
            testsFolder = fileparts(mfilename('fullpath'));
            sourceFolder = fullfile(fileparts(testsFolder), 'src', 'webprogress');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(sourceFolder));
            for folderName = ["fixtures", "helpers"]
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                    fullfile(testsFolder, folderName)));
            end
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

        function testStartBytesCountTowardProgress(testCase)
            % A resumed download receives only the rest of the file, and
            % the bytes already on disk count toward its progress.
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0, ...
                'FileSizeBytes', testCase.FileSizeBytes, 'StartBytes', 4 * 2^20);
            monitor.Direction = matlab.net.http.MessageType.Response;

            output = captureOutput(@() setValues(monitor, 1 * 2^20));

            testCase.verifyEqual(monitor.PercentTransferred, 50, 'AbsTol', 1e-12)
            testCase.verifySubstring(output, '5 MB/10 MB (50%)')
        end

        function testStartBytesCanBeSetAfterCreation(testCase)
            monitor = createCommandWindowMonitor(testCase.FileSizeBytes, 'data.bin');
            monitor.StartBytes = 8 * 2^20;

            captureOutput(@() setValues(monitor, 1 * 2^20));

            testCase.verifyEqual(monitor.PercentTransferred, 90, 'AbsTol', 1e-12)
            testCase.verifyEqual(monitor.TransferredMb, 9)
        end

        function testMultipartProgressCoversWholeFile(testCase)
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0);
            monitor.Direction = matlab.net.http.MessageType.Request;

            firstPart = captureOutput(@() setValues(monitor, 2 * 2^20));
            monitor.addCompletedBytes(2 * 2^20);
            secondPart = captureOutput(@() setValues(monitor, 1 * 2^20));

            testCase.verifySubstring(firstPart, 'Uploaded 2 MB/10 MB (20%)')
            testCase.verifySubstring(secondPart, 'Uploaded 3 MB/10 MB (30%)')
        end

        function testMultipartIgnoresResponseBytes(testCase)
            % The response to a part carries no file bytes. Its size must
            % neither add to the progress nor replace the sent bytes.
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0);
            monitor.Direction = matlab.net.http.MessageType.Request;
            captureOutput(@() setValues(monitor, 1 * 2^20));

            monitor.Direction = matlab.net.http.MessageType.Response;
            output = captureOutput(@() setValues(monitor, 2048));

            testCase.verifyEmpty(output)
            testCase.verifyEqual(monitor.TransferredMb, 1)
            testCase.verifyEqual(monitor.PercentTransferred, 10, 'AbsTol', 1e-12)
        end

        function testMultipartStartsAtCompletedBytes(testCase)
            % A monitor that continues an upload counts the parts the
            % server accepted before it, on the display and in the
            % reports to ProgressFcn.
            spy = TransferCallbackSpy();
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0, ...
                'CompletedBytes', 4 * 2^20, 'ProgressFcn', @spy.record);
            monitor.Direction = matlab.net.http.MessageType.Request;

            output = captureOutput(@() setValues(monitor, 1 * 2^20));
            monitor.addCompletedBytes(1 * 2^20);

            testCase.verifySubstring(output, 'Uploaded 5 MB/10 MB (50%)')
            testCase.verifyEqual(spy.Reports(1).TransferredBytes, 5 * 2^20)
            testCase.verifyEqual(monitor.CompletedBytes, 5 * 2^20)
        end

        function testMultipartCompletedBytesAboveTotalErrors(testCase)
            testCase.verifyError(@() webprogress.MultipartProgressMonitor(1000, ...
                'CompletedBytes', 1001), 'webprogress:progressMonitor:CompletedBytesAboveTotal')
        end

        function testMultipartDisplayStaysOpenAfterRequest(testCase)
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0);
            monitor.Direction = matlab.net.http.MessageType.Request;
            captureOutput(@() setValues(monitor, 2 * 2^20));

            output = captureOutput(@() monitor.done());

            testCase.verifyEmpty(output)
        end

        function testMultipartCloseCountsCompletedParts(testCase)
            % The last part fails, so it is not added and does not count.
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0);
            monitor.Direction = matlab.net.http.MessageType.Request;
            captureOutput(@() setValues(monitor, 3 * 2^20));
            monitor.addCompletedBytes(3 * 2^20);
            captureOutput(@() setValues(monitor, 2 * 2^20));

            output = captureOutput(@() close(monitor));

            testCase.verifySubstring(output, 'Uploaded 3 MB/10 MB (30%). Completed in')
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

        function testCompletionTimeStartsAtFirstByte(testCase)
            % A monitor may exist for a while before its transfer, as a
            % MultipartProgressMonitor does between parts. That time is
            % not part of the transfer.
            monitor = createCommandWindowMonitor(testCase.FileSizeBytes, 'data.bin');
            pause(1.2)
            captureOutput(@() setValues(monitor, testCase.FileSizeBytes));

            output = captureOutput(@() monitor.done());

            testCase.verifySubstring(output, 'Completed in 0 second')
        end

        function testDisplayModeNonePrintsNothing(testCase)
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'None', 'UpdateInterval', 0, ...
                'FileSizeBytes', testCase.FileSizeBytes);
            monitor.Direction = matlab.net.http.MessageType.Response;

            output = captureOutput(@() setValues(monitor, [2, 5, 10] * 2^20));
            output = [output, captureOutput(@() monitor.done())];

            testCase.verifyEmpty(output)
        end

        function testProgressFcnReceivesBytes(testCase)
            spy = TransferCallbackSpy();
            monitor = createSilentMonitor(testCase.FileSizeBytes, spy);
            monitor.StartBytes = 4 * 2^20;

            setValues(monitor, [1, 3] * 2^20)

            testCase.verifyNumElements(spy.Reports, 2)
            testCase.verifyEqual(spy.Reports(1).ActionName, "Download")
            testCase.verifyEqual(spy.Reports(1).TransferredBytes, 5 * 2^20)
            testCase.verifyEqual(spy.Reports(2).TransferredBytes, 7 * 2^20)
            testCase.verifyEqual(spy.Reports(2).TotalBytes, testCase.FileSizeBytes)
        end

        function testProgressFcnFollowsUpdateInterval(testCase)
            % The first report is immediate and the next ones wait for
            % UpdateInterval. done reports the bytes the throttle held
            % back, so the last report gives the final count.
            spy = TransferCallbackSpy();
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'None', 'UpdateInterval', 3600, ...
                'FileSizeBytes', testCase.FileSizeBytes, ...
                'ProgressFcn', @spy.record);
            monitor.Direction = matlab.net.http.MessageType.Response;

            setValues(monitor, [2, 5, 10] * 2^20)
            numReportsBeforeDone = numel(spy.Reports);
            monitor.done()

            testCase.verifyEqual(numReportsBeforeDone, 1)
            testCase.verifyEqual(spy.Reports(end).TransferredBytes, testCase.FileSizeBytes)
        end

        function testProgressFcnIsCalledWithCommandWindowDisplay(testCase)
            spy = TransferCallbackSpy();
            monitor = webprogress.FileTransferProgressMonitor( ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0, ...
                'FileSizeBytes', testCase.FileSizeBytes, ...
                'ProgressFcn', @spy.record);
            monitor.Direction = matlab.net.http.MessageType.Response;

            output = captureOutput(@() setValues(monitor, 2 * 2^20));

            testCase.verifySubstring(output, 'Downloaded 2 MB/10 MB (20%)')
            testCase.verifyNumElements(spy.Reports, 1)
        end

        function testProgressFcnReportsUnknownSizeAsNaN(testCase)
            spy = TransferCallbackSpy();
            monitor = createSilentMonitor(NaN, spy);

            setValues(monitor, 3 * 2^20)

            testCase.verifyEqual(spy.Reports(1).TransferredBytes, 3 * 2^20)
            testCase.verifyTrue(isnan(spy.Reports(1).TotalBytes))
        end

        function testDoneWithoutProgressDoesNotReport(testCase)
            spy = TransferCallbackSpy();
            monitor = createSilentMonitor(testCase.FileSizeBytes, spy);

            monitor.done()

            testCase.verifyEmpty(spy.Reports)
        end

        function testCancelRequestedFcnStopsTransfer(testCase)
            % The spy asks for a stop after the first report. The
            % next report raises the error that aborts the transfer, and
            % the monitor reports nothing more, including from done.
            spy = TransferCallbackSpy(1);
            monitor = createSilentMonitor(testCase.FileSizeBytes, spy);

            setValues(monitor, 1 * 2^20)
            testCase.verifyError(@() setValues(monitor, 2 * 2^20), ...
                'webprogress:progressMonitor:Cancelled')
            monitor.done()

            testCase.verifyNumElements(spy.Reports, 1)
            testCase.verifyEqual(spy.NumCancelChecks, 2)
        end

        function testReportAfterCancelStopsTransfer(testCase)
            % A cancel can arrive between reports, as from the waitbar's
            % Cancel button. Every later report stops the transfer.
            spy = TransferCallbackSpy(1);
            monitor = createSilentMonitor(testCase.FileSizeBytes, spy);
            setValues(monitor, 1 * 2^20)
            testCase.verifyError(@() setValues(monitor, 2 * 2^20), ...
                'webprogress:progressMonitor:Cancelled')

            testCase.verifyError(@() setValues(monitor, 3 * 2^20), ...
                'webprogress:progressMonitor:Cancelled')
            testCase.verifyEqual(spy.NumCancelChecks, 2)
        end

        function testMultipartProgressFcnCoversWholeFile(testCase)
            spy = TransferCallbackSpy();
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'None', 'UpdateInterval', 0, ...
                'ProgressFcn', @spy.record);
            monitor.Direction = matlab.net.http.MessageType.Request;

            setValues(monitor, 2 * 2^20)
            monitor.addCompletedBytes(2 * 2^20);
            setValues(monitor, 1 * 2^20)

            testCase.verifyEqual(spy.Reports(end).ActionName, "Upload")
            testCase.verifyEqual(spy.Reports(end).TransferredBytes, 3 * 2^20)
            testCase.verifyEqual(spy.Reports(end).TotalBytes, testCase.FileSizeBytes)
        end

        function testMultipartCancelRequestedFcnCancels(testCase)
            spy = TransferCallbackSpy(1);
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'None', 'UpdateInterval', 0, ...
                'ProgressFcn', @spy.record, ...
                'CancelRequestedFcn', @spy.isCancelRequested);
            monitor.Direction = matlab.net.http.MessageType.Request;
            setValues(monitor, 1 * 2^20)

            testCase.verifyError(@() setValues(monitor, 2 * 2^20), ...
                'webprogress:progressMonitor:Cancelled')
            testCase.verifyTrue(monitor.IsCancelled)
        end

        function testMultipartCancelDuringResponseStopsTransfer(testCase)
            % The response to a part carries no progress, but a cancel
            % that arrives while it is received must still stop it.
            spy = TransferCallbackSpy(0);
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'None', 'UpdateInterval', 0, ...
                'CancelRequestedFcn', @spy.isCancelRequested);
            monitor.Direction = matlab.net.http.MessageType.Response;

            testCase.verifyError(@() setValues(monitor, 100), ...
                'webprogress:progressMonitor:Cancelled')
            testCase.verifyTrue(monitor.IsCancelled)
        end

        function testIsCancelledAsksCancelRequestedFcn(testCase)
            % webprogress.upload reads IsCancelled before it sends a part,
            % so a cancel requested between two parts stops the next one
            % before any byte is sent.
            spy = TransferCallbackSpy(0);
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'None', 'CancelRequestedFcn', @spy.isCancelRequested);

            testCase.verifyTrue(monitor.IsCancelled)
            testCase.verifyEqual(spy.NumCancelChecks, 1)
        end

        function testCompletedPartIsReportedAtOnce(testCase)
            % The throttle holds back the last bytes of a part, and
            % counting the part reports them without waiting.
            spy = TransferCallbackSpy();
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'None', 'UpdateInterval', 3600, ...
                'ProgressFcn', @spy.record);
            monitor.Direction = matlab.net.http.MessageType.Request;
            setValues(monitor, [1, 2] * 2^20)
            numReportsBeforeCount = numel(spy.Reports);

            monitor.addCompletedBytes(2 * 2^20);

            testCase.verifyEqual(numReportsBeforeCount, 1)
            testCase.verifyEqual(spy.Reports(end).TransferredBytes, 2 * 2^20)
        end

        function testMultipartCloseAfterCancelPrintsNoCompletion(testCase)
            % A cancelled upload is not complete, so close prints no
            % completion message after the last progress line.
            spy = TransferCallbackSpy(1);
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0, ...
                'ProgressFcn', @spy.record, ...
                'CancelRequestedFcn', @spy.isCancelRequested);
            monitor.Direction = matlab.net.http.MessageType.Request;
            captureOutput(@() setValues(monitor, 1 * 2^20));
            testCase.verifyError(@() captureOutput(@() setValues(monitor, 2 * 2^20)), ...
                'webprogress:progressMonitor:Cancelled')

            output = captureOutput(@() close(monitor));

            testCase.verifyEmpty(output)
        end

        function testInvalidProgressFcnErrors(testCase)
            testCase.verifyError( ...
                @() webprogress.FileTransferProgressMonitor('ProgressFcn', 'disp'), ...
                'webprogress:validators:InvalidFunctionHandle')
            testCase.verifyError( ...
                @() webprogress.FileTransferProgressMonitor('CancelRequestedFcn', true), ...
                'webprogress:validators:InvalidFunctionHandle')
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

        function testWaitbarCancelStopsTransfer(testCase)
            % The Cancel button closes the waitbar at once, and the next
            % report stops the transfer without reopening it.
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
            testCase.verifyEmpty(findWaitbars())

            testCase.verifyError(@() setValues(monitor, 200), ...
                'webprogress:progressMonitor:Cancelled')
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

function monitor = createSilentMonitor(fileSizeBytes, spy)
    %createSilentMonitor - Create a monitor that reports every update to a spy
    monitor = webprogress.FileTransferProgressMonitor( ...
        'DisplayMode', 'None', 'UpdateInterval', 0, ...
        'FileSizeBytes', fileSizeBytes, ...
        'ProgressFcn', @spy.record, ...
        'CancelRequestedFcn', @spy.isCancelRequested);
    monitor.Direction = matlab.net.http.MessageType.Response;
end

function setValues(monitor, values)
    %setValues - Set Value once for each byte count, as a transfer does
    for value = values
        monitor.Value = uint64(value);
    end
end
