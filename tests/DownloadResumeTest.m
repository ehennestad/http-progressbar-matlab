classdef DownloadResumeTest < matlab.unittest.TestCase
    %DownloadResumeTest - Tests for webprogress.download with Resume=true
    %   The tests download from a local server that honours byte ranges
    %   and If-Range. A first download is cut short with the truncate
    %   query option, which leaves a partial file, and a second download
    %   continues it. The tests are skipped when python3 or a Unix shell is
    %   unavailable.

    properties (TestParameter)
        % State files that do not hold a saved state: one cut off while
        % it was written, an empty one, and two of another shape.
        invalidState = struct( ...
            'truncated', '{"ETag":"', ...
            'empty', '', ...
            'array', '[]', ...
            'numericETag', '{"ETag":1,"TotalBytes":50}');
    end

    properties (Constant)
        FirstPartBytes = 20 % Bytes after which the server cuts off a first download
    end

    properties
        ServerUrl string % Address of the local HTTP server
        Folder           % Empty folder that is deleted after each test
        Target           % Path of the file to download
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
        function createTemporaryFolder(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = fixture.Folder;
            testCase.Target = fullfile(testCase.Folder, 'data.txt');
        end
    end

    methods (Test)
        function testTruncatedDownloadKeepsPartialFiles(testCase)
            content = repmat('0123456789', 1, 5);

            testCase.downloadFirstPart(testCase.fileUrl('content', content))

            testCase.verifyEqual(listFiles(testCase.Folder), ...
                ["data.txt.part", "data.txt.part.json"])
            testCase.verifyEqual(fileread(testCase.Target + ".part"), content(1:testCase.FirstPartBytes))
        end

        function testResumedDownloadCompletesFile(testCase)
            content = repmat('0123456789', 1, 5);
            url = testCase.fileUrl('content', content);
            testCase.downloadFirstPart(url)

            savedPath = downloadQuietly(testCase.Target, url);

            testCase.verifyEqual(fileread(testCase.Target), content)
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
            testCase.verifyTrue(endsWith(savedPath, filesep + "data.txt"))
        end

        function testResumeAppendsOnlyRemainingBytes(testCase)
            % Both responses carry the same ETag, so the server sends
            % the second body from byte FirstPartBytes onward. A download
            % from the start would give only "b".
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1'));

            numBytes = testCase.FirstPartBytes;
            testCase.verifyEqual(fileread(testCase.Target), ...
                [repmat('a', 1, numBytes), repmat('b', 1, 50 - numBytes)])
        end

        function testChangedFileIsDownloadedFromStart(testCase)
            % The ETag is made from the body, so the second body has
            % another ETag. The server ignores If-Range and sends the
            % range anyway, which the ETag comparison rejects.
            testCase.downloadFirstPart(testCase.fileUrl('content', repmat('a', 1, 50)))

            downloadQuietly(testCase.Target, testCase.fileUrl('content', repmat('b', 1, 50)));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testIgnoredRangeGivesWholeFile(testCase)
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1', 'ignore_range', '1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
        end

        function testCompletePartialFileIsNotDownloadedAgain(testCase)
            % The partial file holds the whole file of FirstPartBytes
            % bytes that the state file describes, as after an
            % interruption between the last byte and the move. The range
            % from byte FirstPartBytes gets status 416. A new download
            % would give "b".
            numBytes = testCase.FirstPartBytes;
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))
            writeText(testCase.Target + ".part.json", ...
                sprintf('{"ETag":"\\"e1\\"","TotalBytes":%d}', numBytes))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, numBytes), 'etag', 'e1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('a', 1, numBytes))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testChangedFileWithCompletePartialFileIsDownloadedFromStart(testCase)
            % The partial file holds the whole file the state file
            % describes, but the file on the server has another ETag, so
            % the 416 answers for a changed file.
            numBytes = testCase.FirstPartBytes;
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))
            writeText(testCase.Target + ".part.json", ...
                sprintf('{"ETag":"\\"e1\\"","TotalBytes":%d}', numBytes))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 10), 'etag', 'e2'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 10))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testUnknownSavedLengthIsResumed(testCase)
            % A first response without Content-Length saves the length as
            % null. The resume is checked by the ETag alone.
            content = repmat('0123456789', 1, 5);
            url = testCase.fileUrl('content', content, 'etag', 'e1');
            testCase.downloadFirstPart(url)
            writeText(testCase.Target + ".part.json", '{"ETag":"\"e1\"","TotalBytes":null}')

            downloadQuietly(testCase.Target, url);

            testCase.verifyEqual(fileread(testCase.Target), content)
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testPartialFileLongerThanFileIsDownloadedFromStart(testCase)
            % The server answers the range from byte FirstPartBytes with
            % status 416, and the partial file is shorter than the 50
            % bytes the state file describes, so it cannot hold the whole
            % file.
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 10), 'etag', 'e1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 10))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testFailedRequestLeavesPartialFilesUnchanged(testCase)
            testCase.downloadFirstPart(testCase.fileUrl('content', repmat('a', 1, 50)))
            partBefore = readBytes(testCase.Target + ".part");
            stateBefore = readBytes(testCase.Target + ".part.json");

            testCase.verifyError(@() downloadQuietly(testCase.Target, ...
                testCase.ServerUrl + "/403"), 'webprogress:download:RequestFailed')

            testCase.verifyEqual(readBytes(testCase.Target + ".part"), partBefore)
            testCase.verifyEqual(readBytes(testCase.Target + ".part.json"), stateBefore)
            testCase.verifyEqual(listFiles(testCase.Folder), ...
                ["data.txt.part", "data.txt.part.json"])
        end

        function testTruncatedResumeKeepsPartialFiles(testCase)
            % The resumed transfer is cut off as well, after 10 of its 30
            % bytes, and a third call completes the file.
            content = repmat('0123456789', 1, 5);
            url = testCase.fileUrl('content', content);
            testCase.downloadFirstPart(url)

            testCase.verifyError(@() downloadQuietly(testCase.Target, url + "&truncate=10"), ...
                'webprogress:download:IncompleteTransfer')

            testCase.verifyEqual(fileread(testCase.Target + ".part"), content(1:30))
            testCase.verifyEqual(listFiles(testCase.Folder), ...
                ["data.txt.part", "data.txt.part.json"])

            downloadQuietly(testCase.Target, url);

            testCase.verifyEqual(fileread(testCase.Target), content)
        end

        function testUnknownCompleteLengthIsChecked(testCase)
            % Content-Range gives the complete length as "*", so the end
            % of the range is what the received size is checked against.
            content = repmat('0123456789', 1, 5);
            url = testCase.fileUrl('content', content, 'complete_length', '*');
            testCase.downloadFirstPart(url)

            testCase.verifyError(@() downloadQuietly(testCase.Target, url + "&truncate=10"), ...
                'webprogress:download:IncompleteTransfer')

            testCase.verifyEqual(fileread(testCase.Target + ".part"), content(1:30))
            testCase.verifyEqual(listFiles(testCase.Folder), ...
                ["data.txt.part", "data.txt.part.json"])
        end

        function testUnknownCompleteLengthCompletesFile(testCase)
            content = repmat('0123456789', 1, 5);
            url = testCase.fileUrl('content', content, 'complete_length', '*');
            testCase.downloadFirstPart(url)

            downloadQuietly(testCase.Target, url);

            testCase.verifyEqual(fileread(testCase.Target), content)
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testRangeFromWrongByteIsDownloadedFromStart(testCase)
            % The server answers the range from byte FirstPartBytes with
            % a 206 that starts at byte 0, which cannot be appended.
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1', 'range_start', '0'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testChangedLengthIsDownloadedFromStart(testCase)
            % The ETag is unchanged, but the file on the server is longer
            % than the 50 bytes the state file describes.
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 60), 'etag', 'e1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 60))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testCompressedResumeErrorsAndKeepsPartialFiles(testCase)
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))
            partBefore = readBytes(testCase.Target + ".part");
            stateBefore = readBytes(testCase.Target + ".part.json");

            testCase.verifyError(@() downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1', 'gzip', '1')), ...
                'webprogress:download:ContentEncoded')

            testCase.verifyEqual(readBytes(testCase.Target + ".part"), partBefore)
            testCase.verifyEqual(readBytes(testCase.Target + ".part.json"), stateBefore)
        end

        function testCompressedDownloadErrorsAndLeavesNoFiles(testCase)
            testCase.verifyError(@() downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'gzip', '1')), ...
                'webprogress:download:ContentEncoded')

            testCase.verifyEmpty(listFiles(testCase.Folder))
        end

        function testStateFileIsWrittenBeforeBody(testCase)
            % The connection closes before the first byte of the body,
            % and the state file is already there.
            url = testCase.fileUrl('content', repmat('a', 1, 50), 'truncate', '0');

            testCase.verifyError(@() downloadQuietly(testCase.Target, url), ...
                'webprogress:download:IncompleteTransfer')

            testCase.verifyTrue(isfile(testCase.Target + ".part.json"))
        end

        function testResumeRequestsSendExpectedHeaders(testCase)
            % Every request asks for the identity coding. The second asks
            % for the rest of the file on the condition that it still has
            % the saved ETag, quotes included, which a server that honours
            % If-Range compares byte for byte.
            url = testCase.fileUrl('content', repmat('a', 1, 50), 'etag', 'e1');
            testCase.downloadFirstPart(url)
            downloadQuietly(testCase.Target, url);

            requests = testCase.readFileRequests();

            testCase.assertGreaterThanOrEqual(numel(requests), 2)
            testCase.verifyEqual(requests{end-1}.headers.Accept_Encoding, 'identity')
            testCase.verifyEqual(requests{end}.headers.Accept_Encoding, 'identity')
            testCase.verifyEqual(requests{end}.headers.Range, ...
                sprintf('bytes=%d-', testCase.FirstPartBytes))
            testCase.verifyEqual(requests{end}.headers.If_Range, '"e1"')
        end

        function testFirstFailedRequestLeavesNoFiles(testCase)
            testCase.verifyError(@() downloadQuietly(testCase.Target, ...
                testCase.ServerUrl + "/403"), 'webprogress:download:RequestFailed')

            testCase.verifyEmpty(listFiles(testCase.Folder))
        end

        function testWeakEntityTagIsDownloadedFromStart(testCase)
            % A weak ETag cannot tell that two responses carry the same
            % bytes, so no state file is kept. The server would honour a
            % range, which would give "a" followed by "b".
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1', 'weak', '1'))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt.part")

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1', 'weak', '1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
        end

        function testMissingEntityTagIsDownloadedFromStart(testCase)
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'no_etag', '1'))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt.part")

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'no_etag', '1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testIncompleteDownloadWithoutETagDoesNotAdviseResume(testCase)
            % Without an ETag no state file is written, so a later call
            % with Resume=true would start from the beginning. The error
            % must not tell the user otherwise.
            import matlab.unittest.constraints.ContainsSubstring
            url = testCase.fileUrl('content', repmat('a', 1, 50), 'no_etag', '1', ...
                'truncate', '20');

            errorId = '';
            message = '';
            try
                downloadQuietly(testCase.Target, url);
            catch exception
                errorId = exception.identifier;
                message = exception.message;
            end

            testCase.verifyEqual(errorId, 'webprogress:download:IncompleteTransfer')
            testCase.verifyThat(message, ContainsSubstring('no ETag'))
            testCase.verifyThat(message, ~ContainsSubstring('Resume=true'))
        end

        function testWeakEntityTagInStateFileIsNotUsed(testCase)
            url = testCase.fileUrl('content', repmat('a', 1, 50), 'etag', 'e1');
            testCase.downloadFirstPart(url)
            writeText(testCase.Target + ".part.json", ...
                '{"ETag":"W/\"e1\"","TotalBytes":50}')

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
        end

        function testMissingStateFileIsDownloadedFromStart(testCase)
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))
            delete(testCase.Target + ".part.json")

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testInvalidStateFileIsDownloadedFromStart(testCase, invalidState)
            % A state file that does not hold a saved state, such as one
            % cut off while it was written, counts as none. The server
            % would honour a range, which would give "a" followed by "b".
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))
            writeText(testCase.Target + ".part.json", invalidState)

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testExistingFileIsReplacedAfterResume(testCase)
            writeText(testCase.Target, 'old')
            content = repmat('0123456789', 1, 5);
            url = testCase.fileUrl('content', content);
            testCase.downloadFirstPart(url)
            testCase.verifyEqual(fileread(testCase.Target), 'old')

            downloadQuietly(testCase.Target, url);

            testCase.verifyEqual(fileread(testCase.Target), content)
        end

        function testFolderTargetErrors(testCase)
            testCase.verifyError(@() downloadQuietly(testCase.Folder, ...
                testCase.fileUrl('content', 'data')), ...
                'webprogress:download:FolderTargetNotResumable')

            testCase.verifyEmpty(listFiles(testCase.Folder))
        end

        function testProgressIncludesResumedBytes(testCase)
            % The second response carries the last 1 MB of a 3 MB file.
            fileSize = 3 * 2^20;
            url = testCase.fileUrl('size', string(fileSize));
            testCase.downloadFirstPart(url, 2 * 2^20)

            % The HTTP stack calls the monitor only once the transfer has
            % lasted a moment, which a local transfer of 1 MB may not.
            output = downloadWithOutput(testCase.Target, url + "&delay=0.5");

            testCase.verifySubstring(output, '3 MB/3 MB (100%)')
            testCase.verifyEqual(readBytes(testCase.Target), ...
                uint8(mod((0:fileSize-1)', 251)))
        end
    end

    methods (Access = private)
        function url = fileUrl(testCase, varargin)
            %fileUrl - Return the URL of the served file with query options
            url = testCase.ServerUrl + "/files/data.txt";
            if ~isempty(varargin)
                pairs = string(varargin);
                query = strjoin(pairs(1:2:end) + "=" + pairs(2:2:end), "&");
                url = url + "?" + query;
            end
        end

        function requests = readFileRequests(testCase)
            %readFileRequests - Return the file requests the server has received
            %   The result is a cell array of structs. jsondecode gives a
            %   struct array instead when every request has the same
            %   headers, and names a header such as Accept-Encoding
            %   Accept_Encoding.
            requestsFile = fullfile(testCase.Folder, 'requests.json');
            evalc(['webprogress.download(requestsFile, testCase.ServerUrl + "/requests", ', ...
                '''DisplayMode'', ''Command Window'');']);
            requests = jsondecode(fileread(requestsFile));
            delete(requestsFile)
            if isstruct(requests)
                requests = num2cell(requests);
            end
        end

        function downloadFirstPart(testCase, url, numBytes)
            %downloadFirstPart - Download a file the server cuts off after numBytes bytes
            %   numBytes is FirstPartBytes by default. The download is the
            %   setup of the test, so a download that is not cut off
            %   stops the test.
            arguments
                testCase
                url (1,1) string
                numBytes (1,1) double = testCase.FirstPartBytes
            end
            url = url + "&truncate=" + string(numBytes);
            testCase.assertError(@() downloadQuietly(testCase.Target, url), ...
                'webprogress:download:IncompleteTransfer')
        end
    end
end

function savedPath = downloadQuietly(target, url) %#ok<INUSD> used inside evalc
    %downloadQuietly - Download with Resume=true without printing progress
    savedPath = '';
    evalc(['savedPath = webprogress.download(target, url, ', ...
        '''DisplayMode'', ''Command Window'', ''Resume'', true);']);
end

function output = downloadWithOutput(target, url) %#ok<INUSD> used inside evalc
    %downloadWithOutput - Download with Resume=true and return the printed progress
    output = evalc(['webprogress.download(target, url, ', ...
        '''DisplayMode'', ''Command Window'', ''Resume'', true);']);
end

function names = listFiles(folder)
    %listFiles - Return the names of the files in a folder in sorted order
    listing = dir(folder);
    names = sort(string({listing(~[listing.isdir]).name}));
end

function writeText(filePath, text)
    %writeText - Write text to a file, replacing its contents
    fileId = fopen(filePath, 'w');
    fwrite(fileId, text);
    fclose(fileId);
end

function bytes = readBytes(filePath)
    %readBytes - Return the contents of a file as bytes
    fileId = fopen(filePath, 'r');
    bytes = fread(fileId, Inf, '*uint8');
    fclose(fileId);
end
