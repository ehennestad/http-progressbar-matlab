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

        function testFractionalNumBytesErrors(testCase)
            testCase.verifyError(@() testCase.uploadToEcho('NumBytes', 1.5), ...
                'webprogress:upload:InvalidNumBytes')
        end

        function testPartsShareOneDisplay(testCase)
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
            monitor = webprogress.MultipartProgressMonitor(testCase.FileSizeBytes, ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0);
            testCase.addTeardown(@() delete(monitor))

            wasSuccess = true;
            evalc(['wasSuccess = webprogress.upload(testCase.FilePath, ', ...
                'testCase.ServerUrl + "/500", ''NumBytes'', 1000, ', ...
                '''ProgressMonitor'', monitor);']);

            testCase.verifyFalse(wasSuccess)
            testCase.verifyEqual(monitor.CompletedBytes, 0)
        end
    end

    methods (Access = private)
        function echo = uploadToEcho(testCase, varargin)
            %uploadToEcho - Upload to /echo and return the decoded reply
            response = matlab.net.http.ResponseMessage.empty; %#ok<NASGU> set inside evalc
            filePath = testCase.FilePath; %#ok<NASGU> used inside evalc
            url = testCase.ServerUrl + "/echo"; %#ok<NASGU> used inside evalc
            evalc(['[~, response] = webprogress.upload(filePath, url, ', ...
                '''DisplayMode'', ''Command Window'', varargin{:});']);
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

function output = captureOutput(fcn) %#ok<INUSD> fcn is called inside evalc
    %captureOutput - Call a function and return its Command Window output
    output = evalc('fcn()');
end
