classdef ProgressCallbackTest < matlab.unittest.TestCase
    %ProgressCallbackTest - Tests for ProgressFcn and CancelRequestedFcn
    %   The tests transfer files to and from a local server with
    %   DisplayMode "None", and record the progress with a ProgressRecorder.
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
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testsFolder, 'fixtures')));
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
            recorder = ProgressRecorder();
            target = fullfile(testCase.Folder, 'data.bin');
            url = testCase.sizedFileUrl(); %#ok<NASGU> used inside evalc

            output = evalc(['webprogress.download(target, url, ', ...
                '"DisplayMode", "None", "ProgressFcn", @recorder.record);']);

            testCase.verifyEmpty(output)
            testCase.verifyNotEmpty(recorder.Reports)
            testCase.verifyEqual([recorder.Reports.ActionName], ...
                repmat("Download", 1, numel(recorder.Reports)))
            testCase.verifyEqual(recorder.Reports(end).TransferredBytes, testCase.FileSizeBytes)
            testCase.verifyEqual(recorder.Reports(end).TotalBytes, testCase.FileSizeBytes)
        end

        function testUploadReportsWholeFile(testCase)
            recorder = ProgressRecorder();
            filePath = testCase.FilePath; %#ok<NASGU> used inside evalc
            url = testCase.statusUrl(201); %#ok<NASGU> used inside evalc

            output = evalc(['webprogress.upload(filePath, url, ', ...
                '"DisplayMode", "None", "ProgressFcn", @recorder.record);']);

            testCase.verifyEmpty(output)
            testCase.verifyNotEmpty(recorder.Reports)
            testCase.verifyEqual(recorder.Reports(end).ActionName, "Upload")
            testCase.verifyEqual(recorder.Reports(end).TransferredBytes, testCase.FileSizeBytes)
            testCase.verifyEqual(recorder.Reports(end).TotalBytes, testCase.FileSizeBytes)
        end

        function testDownloadCancelledBeforeStartSendsNothing(testCase)
            recorder = ProgressRecorder(0);
            target = fullfile(testCase.Folder, 'data.bin');

            testCase.verifyError(@() webprogress.download(target, testCase.sizedFileUrl(), ...
                'DisplayMode', 'None', 'CancelRequestedFcn', @recorder.isCancelRequested), ...
                'webprogress:download:Cancelled')

            testCase.verifyEqual(recorder.NumCancelChecks, 1)
            testCase.verifyEqual(listFiles(testCase.Folder), "upload.bin")
        end

        function testDownloadCancelledDuringTransferSavesNoFile(testCase)
            % The server pauses after the first byte, so the transfer is
            % still running when the recorder asks for it to stop.
            recorder = ProgressRecorder(1);
            target = fullfile(testCase.Folder, 'data.bin');
            url = testCase.sizedFileUrl("delay", 1);

            testCase.verifyError(@() webprogress.download(target, url, ...
                'DisplayMode', 'None', 'UpdateInterval', 0.001, ...
                'ProgressFcn', @recorder.record, ...
                'CancelRequestedFcn', @recorder.isCancelRequested), ...
                'webprogress:download:Cancelled')

            testCase.verifyEqual(listFiles(testCase.Folder), "upload.bin")
        end

        function testResumableDownloadCancelledKeepsPartialFile(testCase)
            % The state file is written when the headers arrive, so a
            % cancelled download can be continued with Resume=true.
            recorder = ProgressRecorder(1);
            target = fullfile(testCase.Folder, 'data.bin');
            url = testCase.sizedFileUrl("delay", 1);

            testCase.verifyError(@() webprogress.download(target, url, ...
                'DisplayMode', 'None', 'UpdateInterval', 0.001, 'Resume', true, ...
                'ProgressFcn', @recorder.record, ...
                'CancelRequestedFcn', @recorder.isCancelRequested), ...
                'webprogress:download:Cancelled')

            testCase.verifyFalse(isfile(target))
            testCase.verifyTrue(isfile(target + ".part.json"))
        end

        function testUploadCancelledBeforeStartErrors(testCase)
            recorder = ProgressRecorder(0);

            testCase.verifyError(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), 'DisplayMode', 'None', ...
                'CancelRequestedFcn', @recorder.isCancelRequested), ...
                'webprogress:upload:Cancelled')
        end

        function testUploadCancelledErrorsAlsoWithOutputs(testCase)
            % An unsuccessful status is returned rather than raised when
            % upload has outputs. A cancellation is not a status, so it
            % is raised either way.
            recorder = ProgressRecorder(0);

            testCase.verifyError(@() uploadWithOutput(testCase.FilePath, ...
                testCase.statusUrl(201), @recorder.isCancelRequested), ...
                'webprogress:upload:Cancelled')
        end

        function testWithoutCancelRequestTransferCompletes(testCase)
            recorder = ProgressRecorder();
            target = fullfile(testCase.Folder, 'data.bin');

            webprogress.download(target, testCase.sizedFileUrl(), ...
                'DisplayMode', 'None', 'UpdateInterval', 0.001, ...
                'CancelRequestedFcn', @recorder.isCancelRequested);

            fileInfo = dir(target);
            testCase.verifyEqual(fileInfo.bytes, testCase.FileSizeBytes)
            testCase.verifyGreaterThanOrEqual(recorder.NumCancelChecks, 1)
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

function names = listFiles(folder)
    %listFiles - Return the names of the files in a folder
    listing = dir(folder);
    names = string({listing(~[listing.isdir]).name});
end
