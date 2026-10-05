classdef UploadRangeTest < matlab.unittest.TestCase
    %UploadRangeTest - Tests for uploading part of a file with webprogress.upload
    %   The tests upload to a local server whose /echo path answers with a
    %   description of the request body. The bytes of the uploaded file
    %   repeat the values 0 to 250, so every part has its own content. The
    %   tests are skipped when python3 or a Unix shell is unavailable.

    properties (Constant)
        FileSizeBytes = 3 * 2^20
    end

    properties
        ServerUrl string % Address of the local HTTP server
        FilePath         % Local file that the tests upload
        FileBytes        % Contents of the file as a column of bytes
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
        function createUploadFile(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.FilePath = fullfile(fixture.Folder, 'data.bin');
            testCase.FileBytes = uint8(mod((0:testCase.FileSizeBytes-1)', 251));

            fileId = fopen(testCase.FilePath, 'w');
            fwrite(fileId, testCase.FileBytes, 'uint8');
            fclose(fileId);
        end
    end

    methods (Test)
        function testRangeSendsOnlyItsBytes(testCase)
            echo = testCase.uploadToEcho('Offset', 1000, 'NumBytes', 5000);

            testCase.verifyEcho(echo, 1000, 5000)
        end

        function testRangeAnnouncesContentLength(testCase)
            % A range has a known size, so the request announces it in
            % Content-Length and sends the body whole rather than in chunks of
            % unannounced size. A service can then check that the part arrived
            % complete.
            echo = testCase.uploadToEcho('Offset', 1000, 'NumBytes', 5000);

            testCase.verifyEqual(echo.content_length, '5000')
            testCase.verifyEmpty(echo.transfer_encoding)
        end

        function testOffsetAloneSendsRestOfFile(testCase)
            echo = testCase.uploadToEcho('Offset', 2^20 + 7);

            testCase.verifyEcho(echo, 2^20 + 7, testCase.FileSizeBytes - 2^20 - 7)
        end

        function testNumBytesAloneSendsStartOfFile(testCase)
            echo = testCase.uploadToEcho('NumBytes', 300);

            testCase.verifyEcho(echo, 0, 300)
        end

        function testWholeFileIsSentWithoutRange(testCase)
            echo = testCase.uploadToEcho();

            testCase.verifyEcho(echo, 0, testCase.FileSizeBytes)
        end

        function testRangePastEndOfFileErrors(testCase)
            testCase.verifyError(@() testCase.uploadToEcho( ...
                'Offset', testCase.FileSizeBytes - 10, 'NumBytes', 20), ...
                'webprogress:upload:RangeOutsideFile')
        end

        function testOffsetPastEndOfFileErrors(testCase)
            testCase.verifyError(@() testCase.uploadToEcho( ...
                'Offset', testCase.FileSizeBytes + 1), ...
                'webprogress:upload:RangeOutsideFile')
        end

        function testOffsetAtEndOfFileErrors(testCase)
            % A part loop that runs one step too far must not send an
            % empty part.
            testCase.verifyError(@() testCase.uploadToEcho( ...
                'Offset', testCase.FileSizeBytes), ...
                'webprogress:upload:RangeOutsideFile')
        end

        function testMissingFileErrors(testCase)
            % The error comes before any progress is printed.
            missingPath = fullfile(fileparts(testCase.FilePath), 'missing.bin');

            testCase.verifyError(@() webprogress.upload(missingPath, ...
                testCase.ServerUrl + "/echo", 'DisplayMode', 'Command Window'), ...
                'webprogress:upload:FileNotFound')
        end

        function testContentTypeFromRequestMessageIsSent(testCase)
            % A storage service may require the Content-Type of a part.
            % The one given in the request must arrive once, not next to
            % one the provider adds.
            request = matlab.net.http.RequestMessage(matlab.net.http.RequestMethod.PUT, ...
                matlab.net.http.field.ContentTypeField("application/octet-stream"), []);

            echo = testCase.uploadToEcho('Offset', 1000, 'NumBytes', 5000, ...
                'RequestMessage', request);

            testCase.verifyEqual(string(echo.content_types), "application/octet-stream")
        end

        function testRangeIsSentAgainAfterRedirect(testCase)
            % The server answers the first request with 307, and the
            % client sends the request again to the new location. The
            % provider rereads the range from its start for the second
            % request, so the echo describes the whole range.
            [~, ~, response] = captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.ServerUrl + "/redirect", 'Offset', 1000, 'NumBytes', 5000, ...
                DisplayMode="Command Window"));

            testCase.verifyEcho(response.Body.Data, 1000, 5000)
        end

        function testProviderErrorsWhenFileShrinks(testCase)
            % The file loses bytes of the range after the provider was
            % created, as when it is rewritten during an upload. The
            % provider raises an error and closes the file.
            provider = webprogress.internal.FileRangeProvider(testCase.FilePath, 1000, 5000);
            fileId = fopen(testCase.FilePath, 'w');
            fwrite(fileId, testCase.FileBytes(1:3000), 'uint8');
            fclose(fileId);

            testCase.verifyError(@() provider.getData(4096), 'webprogress:upload:FileChanged')

            openFiles = arrayfun(@fopen, listOpenFileIds(), 'UniformOutput', false);
            testCase.verifyFalse(ismember(testCase.FilePath, openFiles))
        end

        function testFractionalNumBytesErrors(testCase)
            testCase.verifyError(@() testCase.uploadToEcho('NumBytes', 1.5), ...
                'webprogress:upload:InvalidNumBytes')
        end

        function testZeroNumBytesErrors(testCase)
            % A part loop whose last step computes 0 bytes must not send
            % an empty part.
            testCase.verifyError(@() testCase.uploadToEcho('NumBytes', 0), ...
                'MATLAB:validators:mustBePositive')
        end

        function testPartsShareOneDisplay(testCase)
            % A file sent in parts shows one display for the whole file, opened
            % once and closed by close(monitor), rather than one per request.
            partSize = 2^20;
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0);
            testCase.addTeardown(@() delete(monitor))

            output = '';
            for offset = 0:partSize:testCase.FileSizeBytes - 1
                output = [output, captureOutput(@() webprogress.upload( ...
                    testCase.FilePath, testCase.ServerUrl + "/echo", ...
                    'Offset', offset, 'NumBytes', partSize, ...
                    'ProgressMonitor', monitor))]; %#ok<AGROW>
            end
            output = [output, captureOutput(@() close(monitor))];

            testCase.verifyEqual(monitor.CompletedBytes, testCase.FileSizeBytes)
            testCase.verifyEqual(count(string(output), "Uploading"), 1)
            testCase.verifySubstring(output, 'Uploaded 3 MB/3 MB (100%). Completed in')
        end

        function testFailedPartIsNotCounted(testCase)
            % A part the server rejects is sent again later, so it must not count
            % toward CompletedBytes, which is what a caller saves to resume.
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0);
            testCase.addTeardown(@() delete(monitor))

            [~, wasSuccess] = captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.ServerUrl + "/500", NumBytes=1000, ProgressMonitor=monitor));

            testCase.verifyFalse(wasSuccess)
            testCase.verifyEqual(monitor.CompletedBytes, 0)
        end
    end

    methods (Access = private)
        function echo = uploadToEcho(testCase, varargin)
            %uploadToEcho - Upload to /echo and return the decoded reply
            [~, ~, response] = captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.ServerUrl + "/echo", varargin{:}, DisplayMode="Command Window"));
            echo = response.Body.Data;
        end

        function verifyEcho(testCase, echo, offset, numBytes)
            %verifyEcho - Verify that the server received bytes offset+1 to offset+numBytes
            expected = testCase.FileBytes(offset+1:offset+numBytes);
            testCase.verifyEqual(echo.length, numBytes)
            testCase.verifyEqual(echo.sum, sum(double(expected)))
            testCase.verifyEqual(echo.head(:), double(expected(1:min(16, end))))
            testCase.verifyEqual(echo.tail(:), double(expected(max(end-15, 1):end)))
        end
    end
end

function fileIds = listOpenFileIds()
    %listOpenFileIds - Return the identifiers of the files MATLAB has open
    %   openedFiles exists from R2024a, and fopen('all') raises a
    %   staged-removal error in later releases, so the release decides.
    if isMATLABReleaseOlderThan("R2024a")
        fileIds = fopen('all');
    else
        fileIds = openedFiles();
    end
end
