classdef UploadTest < matlab.unittest.TestCase
    %UploadTest - Tests for webprogress.upload
    %   The tests upload to a local server that answers with the HTTP status
    %   given in the URL path. They are skipped when python3 or a Unix shell
    %   is unavailable.

    properties (TestParameter)
        successStatus = struct('ok', 200, 'created', 201, 'noContent', 204);
        failureStatus = struct('forbidden', 403, 'serverError', 500);
    end

    properties (Constant)
        FileName = 'upload test.bin'
        FileSizeBytes = 3 * 2^20
    end

    properties
        ServerUrl string % Address of the local HTTP status server
        FilePath         % Local file that the tests upload
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
            testCase.FilePath = fullfile(fixture.Folder, testCase.FileName);

            fileId = fopen(testCase.FilePath, 'w');
            fwrite(fileId, zeros(1, testCase.FileSizeBytes, 'uint8'));
            fclose(fileId);
        end
    end

    methods (Test)
        function testSuccessfulStatusReturnsTrue(testCase, successStatus)
            % A long update interval keeps the monitor from printing.
            wasSuccess = webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(successStatus), ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 3600);

            testCase.verifyTrue(wasSuccess)
        end

        function testUnsuccessfulStatusReturnsFalse(testCase, failureStatus)
            wasSuccess = webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(failureStatus), ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 3600);

            testCase.verifyFalse(wasSuccess)
        end

        function testResponseIsReturned(testCase)
            [~, response] = webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 3600);

            testCase.verifyEqual(response.StatusCode, matlab.net.http.StatusCode.Created)
        end

        function testUnsuccessfulStatusErrorsWithoutOutputs(testCase)
            testCase.verifyError(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(403), ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 3600), ...
                'webprogress:upload:RequestFailed')
        end

        function testCompletionMessageDescribesUpload(testCase)
            import matlab.unittest.constraints.ContainsSubstring

            output = captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0.001));

            testCase.verifySubstring(output, 'Uploaded 3 MB/3 MB (100%). Completed in')
            testCase.verifyThat(output, ~ContainsSubstring('Downloaded'))
        end

        function testTitleShowsLocalFileName(testCase)
            output = captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0.001, ...
                'ShowFilename', true));

            testCase.verifySubstring(output, ['Uploading ', testCase.FileName])
        end
    end

    methods (Access = private)
        function url = statusUrl(testCase, statusCode)
            %statusUrl - Return the server URL that answers with statusCode
            url = sprintf('%s/%d', testCase.ServerUrl, statusCode);
        end
    end
end

function output = captureOutput(fcn) %#ok<INUSD> fcn is called inside evalc
    %captureOutput - Call a function and return its Command Window output
    output = evalc('fcn()');
end
