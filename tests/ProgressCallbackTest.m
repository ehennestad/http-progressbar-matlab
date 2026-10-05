classdef ProgressCallbackTest < matlab.unittest.TestCase
    %ProgressCallbackTest - Tests for ProgressFcn and CancelRequestedFcn
    %   The tests transfer files to and from a local server with
    %   DisplayMode "None", and record the progress with a TransferCallbackSpy.
    %   They are skipped when python3 or a Unix shell is unavailable.

    properties (Constant)
        FileSizeBytes = 3 * 2^20
    end

    properties
        ServerUrl string % Address of the local HTTP server
        Folder           % Empty folder that is deleted after each test
        FilePath         % Local file that the upload tests send
    end

    methods (TestClassSetup)
        function addFoldersToPath(testCase)
            testsFolder = fileparts(mfilename('fullpath'));
            sourceFolder = fullfile(fileparts(testsFolder), 'src', 'webprogress');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(sourceFolder));
            for folderName = ["fixtures", "helpers"]
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                    fullfile(testsFolder, folderName)));
            end
        end

        function startLocalServer(testCase)
            testCase.assumeFalse(ispc, 'The local HTTP server needs a Unix shell.')
            [status, ~] = system('python3 --version');
            testCase.assumeEqual(status, 0, 'The local HTTP server needs python3.')

            fixture = testCase.applyFixture(LocalHttpServerFixture);
            testCase.ServerUrl = fixture.BaseUrl;
        end
    end

    methods (TestMethodSetup)
        function createFolderAndFile(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = fixture.Folder;
            testCase.FilePath = fullfile(fixture.Folder, 'upload.bin');

            fileId = fopen(testCase.FilePath, 'w');
            fwrite(fileId, zeros(testCase.FileSizeBytes, 1, 'uint8'), 'uint8');
            fclose(fileId);
        end
    end

    methods (Test)
        function testDownloadReportsWholeFile(testCase)
            spy = TransferCallbackSpy();
            target = fullfile(testCase.Folder, 'data.bin');

            output = captureOutput(@() webprogress.download(target, testCase.sizedFileUrl(), ...
                DisplayMode="None", ProgressFcn=@spy.record));

            testCase.verifyEmpty(output)
            testCase.verifyNotEmpty(spy.Reports)
            testCase.verifyEqual([spy.Reports.ActionName], ...
                repmat("Download", 1, numel(spy.Reports)))
            testCase.verifyEqual(spy.Reports(end).TransferredBytes, testCase.FileSizeBytes)
            testCase.verifyEqual(spy.Reports(end).TotalBytes, testCase.FileSizeBytes)
        end

        function testUploadReportsWholeFile(testCase)
            spy = TransferCallbackSpy();

            output = captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), DisplayMode="None", ProgressFcn=@spy.record));

            testCase.verifyEmpty(output)
            testCase.verifyNotEmpty(spy.Reports)
            testCase.verifyEqual(spy.Reports(end).ActionName, "Upload")
            testCase.verifyEqual(spy.Reports(end).TransferredBytes, testCase.FileSizeBytes)
            testCase.verifyEqual(spy.Reports(end).TotalBytes, testCase.FileSizeBytes)
        end

        function testUploadReportsOnlyTheFile(testCase)
            % The server answers with a JSON body. Its bytes are not
            % progress of the upload, so every report describes the file.
            spy = TransferCallbackSpy();

            captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.ServerUrl + "/echo", DisplayMode="None", ProgressFcn=@spy.record));

            testCase.verifyEqual([spy.Reports.ActionName], ...
                repmat("Upload", 1, numel(spy.Reports)))
            testCase.verifyEqual(spy.Reports(end).TransferredBytes, testCase.FileSizeBytes)
            testCase.verifyEqual(spy.Reports(end).TotalBytes, testCase.FileSizeBytes)
        end

        function testCancelledMonitorStopsPartBeforeSend(testCase)
            % The monitor's CancelRequestedFcn already asks for a stop, so
            % the part is not sent. The file does not exist, which would
            % raise FileNotFound if the upload got that far.
            spy = TransferCallbackSpy(0);
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'None', 'CancelRequestedFcn', @spy.isCancelRequested);
            missingPath = fullfile(testCase.Folder, 'missing.bin');

            testCase.verifyError(@() webprogress.upload(missingPath, testCase.statusUrl(201), ...
                'NumBytes', 1000, 'ProgressMonitor', monitor), 'webprogress:upload:Cancelled')
        end

        function testDownloadCancelledBeforeStartSendsNothing(testCase)
            spy = TransferCallbackSpy(0);
            target = fullfile(testCase.Folder, 'data.bin');

            testCase.verifyError(@() webprogress.download(target, testCase.sizedFileUrl(), ...
                'DisplayMode', 'None', 'CancelRequestedFcn', @spy.isCancelRequested), ...
                'webprogress:download:Cancelled')

            testCase.verifyEqual(spy.NumCancelChecks, 1)
            testCase.verifyEqual(listFiles(testCase.Folder), "upload.bin")
        end

        function testDownloadCancelledDuringTransferSavesNoFile(testCase)
            % The server pauses after the first byte, so the transfer is
            % still running when the spy asks for it to stop.
            spy = TransferCallbackSpy(1);
            target = fullfile(testCase.Folder, 'data.bin');
            url = testCase.sizedFileUrl("delay", 1);

            testCase.verifyError(@() webprogress.download(target, url, ...
                'DisplayMode', 'None', 'UpdateInterval', 0.001, ...
                'ProgressFcn', @spy.record, ...
                'CancelRequestedFcn', @spy.isCancelRequested), ...
                'webprogress:download:Cancelled')

            testCase.verifyEqual(listFiles(testCase.Folder), "upload.bin")
        end

        function testResumableDownloadCancelledKeepsPartialFile(testCase)
            % The state file is written when the headers arrive, so a
            % cancelled download can be continued with Resume=true.
            spy = TransferCallbackSpy(1);
            target = fullfile(testCase.Folder, 'data.bin');
            url = testCase.sizedFileUrl("delay", 1);

            testCase.verifyError(@() webprogress.download(target, url, ...
                'DisplayMode', 'None', 'UpdateInterval', 0.001, 'Resume', true, ...
                'ProgressFcn', @spy.record, ...
                'CancelRequestedFcn', @spy.isCancelRequested), ...
                'webprogress:download:Cancelled')

            testCase.verifyFalse(isfile(target))
            testCase.verifyTrue(isfile(target + ".part.json"))
        end

        function testUploadCancelledBeforeStartErrors(testCase)
            spy = TransferCallbackSpy(0);

            testCase.verifyError(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), 'DisplayMode', 'None', ...
                'CancelRequestedFcn', @spy.isCancelRequested), ...
                'webprogress:upload:Cancelled')
        end

        function testUploadCancelledErrorsAlsoWithOutputs(testCase)
            % An unsuccessful status is returned rather than raised when
            % upload has outputs. A cancellation is not a status, so it
            % is raised either way.
            spy = TransferCallbackSpy(0);

            testCase.verifyError(@() uploadWithOutput(testCase.FilePath, ...
                testCase.statusUrl(201), @spy.isCancelRequested), ...
                'webprogress:upload:Cancelled')
        end

        function testWithoutCancelRequestTransferCompletes(testCase)
            spy = TransferCallbackSpy();
            target = fullfile(testCase.Folder, 'data.bin');

            webprogress.download(target, testCase.sizedFileUrl(), ...
                'DisplayMode', 'None', 'UpdateInterval', 0.001, ...
                'CancelRequestedFcn', @spy.isCancelRequested);

            fileInfo = dir(target);
            testCase.verifyEqual(fileInfo.bytes, testCase.FileSizeBytes)
            testCase.verifyGreaterThanOrEqual(spy.NumCancelChecks, 1)
        end

        function testCancelRequestedFcnWithNonLogicalResultErrors(testCase)
            target = fullfile(testCase.Folder, 'data.bin');

            testCase.verifyError(@() webprogress.download(target, testCase.sizedFileUrl(), ...
                DisplayMode="None", CancelRequestedFcn=@() "yes"), ...
                'webprogress:validators:InvalidCancelRequestedResult')
            testCase.verifyError(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), DisplayMode="None", CancelRequestedFcn=@() [true, true]), ...
                'webprogress:validators:InvalidCancelRequestedResult')
        end
    end

    methods (Test, TestTags = {'Graphical'})
        function testWaitbarCancelStopsDownload(testCase)
            % The progress callback presses the waitbar's Cancel button
            % while the server pauses, as a user would during a transfer.
            testCase.assumeNotEqual(getenv('GITHUB_ACTIONS'), 'true', ...
                'Figures cannot be created on GitHub Actions runners.')
            testCase.addTeardown(@() delete(findWaitbars()))
            target = fullfile(testCase.Folder, 'data.bin');
            url = testCase.sizedFileUrl("delay", 1);

            testCase.verifyError(@() webprogress.download(target, url, ...
                'UpdateInterval', 0.001, 'ProgressFcn', @(~) pressWaitbarCancel()), ...
                'webprogress:download:Cancelled')

            testCase.verifyEqual(listFiles(testCase.Folder), "upload.bin")
            testCase.verifyEmpty(findWaitbars())
        end
    end

    methods (Access = private)
        function url = sizedFileUrl(testCase, varargin)
            %sizedFileUrl - Return the URL of a served file of FileSizeBytes bytes
            url = sprintf("%s/files/data.bin?size=%d", ...
                testCase.ServerUrl, testCase.FileSizeBytes);
            pairs = string(varargin);
            for i = 1:2:numel(pairs)
                url = url + "&" + pairs(i) + "=" + pairs(i+1);
            end
        end

        function url = statusUrl(testCase, statusCode)
            %statusUrl - Return the URL that answers with statusCode
            url = sprintf("%s/%d", testCase.ServerUrl, statusCode);
        end
    end
end

function wasSuccess = uploadWithOutput(filePath, url, cancelRequestedFcn)
    %uploadWithOutput - Upload with an output, so a failed status is not raised
    wasSuccess = webprogress.upload(filePath, url, 'DisplayMode', 'None', ...
        'CancelRequestedFcn', cancelRequestedFcn);
end

function bars = findWaitbars()
    %findWaitbars - Return the open waitbar figures
    bars = findall(0, 'Type', 'figure', 'Tag', 'TMWWaitbar');
end

function pressWaitbarCancel()
    %pressWaitbarCancel - Press the Cancel button of an open waitbar
    %   The first report comes before the waitbar opens, so there may be
    %   none yet.
    bars = findWaitbars();
    if isempty(bars)
        return
    end
    button = findall(bars(1), 'Style', 'pushbutton');
    callback = button(1).Callback;
    callback(button(1), [])
end
