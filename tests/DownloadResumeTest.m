classdef DownloadResumeTest < matlab.unittest.TestCase
    %DownloadResumeTest - Tests for webprogress.download with Resume=true
    %   The tests download from a local server that honours byte ranges
    %   and If-Range. A first download is cut short with the truncate
    %   query option, which leaves a partial file, and a second download
    %   continues it. The tests are skipped when python3 or a Unix shell is
    %   unavailable.

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
            testCase.verifyEqual(fileread(testCase.Target + ".part"), content(1:20))
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
            % the second body from byte 20 onward. A download from the
            % start would give only "b".
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1'));

            testCase.verifyEqual(fileread(testCase.Target), ...
                [repmat('a', 1, 20), repmat('b', 1, 30)])
        end

        function testChangedFileIsDownloadedFromStart(testCase)
            % The ETag is made from the body, so the second body has
            % another ETag and If-Range makes the server send all of it.
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
            % The server file now has the 20 bytes already received, so
            % the range from byte 20 gets status 416. A new download
            % would give "b".
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 20), 'etag', 'e1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('a', 1, 20))
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testPartialFileLongerThanFileIsDownloadedFromStart(testCase)
            % The server answers the range from byte 20 with status 416
            % and a length of 10, which the partial file cannot be part of.
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

        function testRangeFromWrongByteErrorsAndKeepsPartialFiles(testCase)
            % The server answers the range from byte 20 with a 206 that
            % starts at byte 0, which cannot be appended.
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1'))
            partBefore = readBytes(testCase.Target + ".part");
            stateBefore = readBytes(testCase.Target + ".part.json");

            testCase.verifyError(@() downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1', 'range_start', '0')), ...
                'webprogress:download:UnexpectedRange')

            testCase.verifyEqual(readBytes(testCase.Target + ".part"), partBefore)
            testCase.verifyEqual(readBytes(testCase.Target + ".part.json"), stateBefore)
        end

        function testFirstFailedRequestLeavesNoFiles(testCase)
            testCase.verifyError(@() downloadQuietly(testCase.Target, ...
                testCase.ServerUrl + "/403"), 'webprogress:download:RequestFailed')

            testCase.verifyEmpty(listFiles(testCase.Folder))
        end

        function testWeakEntityTagIsDownloadedFromStart(testCase)
            % If-Range cannot carry a weak ETag. The server honours a
            % range for this ETag, so a resumed download would give "a"
            % followed by "b".
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'etag', 'e1', 'weak', '1'))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'etag', 'e1', 'weak', '1'));

            testCase.verifyEqual(fileread(testCase.Target), repmat('b', 1, 50))
        end

        function testWeakEntityTagInStateFileIsNotUsed(testCase)
            url = testCase.fileUrl('content', repmat('a', 1, 50), 'etag', 'e1');
            testCase.downloadFirstPart(url)
            writeText(testCase.Target + ".part.json", ...
                '{"Validator":"W/\"e1\"","TotalBytes":50}')

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

        function testLastModifiedIsUsedWithoutEntityTag(testCase)
            % The date is long before the Date header of the response,
            % which makes it a strong validator.
            lastModified = "Mon,%2001%20Jan%202024%2000:00:00%20GMT";
            testCase.downloadFirstPart(testCase.fileUrl( ...
                'content', repmat('a', 1, 50), 'last_modified', lastModified))

            downloadQuietly(testCase.Target, testCase.fileUrl( ...
                'content', repmat('b', 1, 50), 'last_modified', lastModified));

            testCase.verifyEqual(fileread(testCase.Target), ...
                [repmat('a', 1, 20), repmat('b', 1, 30)])
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
            testCase.downloadFirstPart(url + "&truncate=" + string(2 * 2^20))

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

        function downloadFirstPart(testCase, url)
            %downloadFirstPart - Download a file the server cuts off after 20 bytes
            %   An explicit truncate option in url takes the place of 20.
            if ~contains(url, "truncate=")
                url = url + "&truncate=20";
            end
            testCase.verifyError(@() downloadQuietly(testCase.Target, url), ...
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
