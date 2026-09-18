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
            wasSuccess = testCase.uploadQuietly(successStatus);

            testCase.verifyTrue(wasSuccess)
        end

        function testUnsuccessfulStatusReturnsFalse(testCase, failureStatus)
            wasSuccess = testCase.uploadQuietly(failureStatus);

            testCase.verifyFalse(wasSuccess)
        end

        function testResponseIsReturned(testCase)
            [~, response] = testCase.uploadQuietly(201);

            testCase.verifyEqual(response.StatusCode, matlab.net.http.StatusCode.Created)
        end

        function testUnsuccessfulStatusErrorsWithoutOutputs(testCase)
            % An unsuccessful status only raises an error when the caller
            % asks for no outputs, so this one cannot go through
            % uploadQuietly.
            testCase.verifyError(@() uploadWithoutOutputs(testCase.FilePath, ...
                testCase.statusUrl(403)), 'webprogress:upload:RequestFailed')
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

        function testTitleShowsGivenFilename(testCase)
            output = captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0.001, ...
                'Filename', 'folder/object name.bin'));

            testCase.verifySubstring(output, 'Uploading folder/object name.bin')
        end

        function testGivenFilenameReplacesLocalFileName(testCase)
            import matlab.unittest.constraints.ContainsSubstring

            output = captureOutput(@() webprogress.upload(testCase.FilePath, ...
                testCase.statusUrl(201), ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0.001, ...
                'ShowFilename', true, 'Filename', 'object name.bin'));

            testCase.verifySubstring(output, 'Uploading object name.bin')
            testCase.verifyThat(output, ~ContainsSubstring(testCase.FileName))
        end
    end

    methods (Access = private)
        function url = statusUrl(testCase, statusCode)
            %statusUrl - Return the server URL that answers with statusCode
            url = sprintf('%s/%d', testCase.ServerUrl, statusCode);
        end

        function [wasSuccess, response] = uploadQuietly(testCase, statusCode)
            %uploadQuietly - Upload without printing progress
            %   The monitor displays the first progress it receives
            %   whatever the update interval, so the output has to be
            %   captured to keep it out of the Command Window.
            filePath = testCase.FilePath; %#ok<NASGU> used inside evalc
            url = testCase.statusUrl(statusCode); %#ok<NASGU> used inside evalc
            wasSuccess = false;
            response = matlab.net.http.ResponseMessage.empty;
            evalc(['[wasSuccess, response] = webprogress.upload(filePath, url, ', ...
                '''DisplayMode'', ''Command Window'');']);
        end
    end
end

function uploadWithoutOutputs(filePath, url) %#ok<INUSD> used inside evalc
    %uploadWithoutOutputs - Upload asking for no outputs, without printing
    %   evalc passes the error raised for an unsuccessful status on to the
    %   caller.
    evalc(['webprogress.upload(filePath, url, ', ...
        '''DisplayMode'', ''Command Window'');']);
end

function output = captureOutput(fcn) %#ok<INUSD> fcn is called inside evalc
    %captureOutput - Call a function and return its Command Window output
    output = evalc('fcn()');
end
