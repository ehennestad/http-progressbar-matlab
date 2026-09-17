classdef DownloadTargetTest < matlab.unittest.TestCase
    %DownloadTargetTest - Tests where webprogress.download saves a file
    %   The tests download from a local server that serves text files and
    %   error pages. They are skipped when python3 or a Unix shell is
    %   unavailable.

    properties
        ServerUrl string % Address of the local HTTP server
        Folder           % Empty folder that is deleted after each test
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
        end
    end

    methods (Test)
        function testFileTargetIsWrittenWithoutAddedExtension(testCase)
            % The server sends text/plain, for which the file consumer
            % would otherwise add ".txt".
            target = fullfile(testCase.Folder, 'LICENSE');

            savedPath = downloadQuietly(target, testCase.fileUrl('LICENSE'));

            testCase.verifyEqual(listFiles(testCase.Folder), "LICENSE")
            testCase.verifyTrue(endsWith(savedPath, filesep + "LICENSE"))
        end

        function testFolderTargetUsesNameFromUrl(testCase)
            downloadQuietly(testCase.Folder, testCase.fileUrl('README'));

            testCase.verifyEqual(listFiles(testCase.Folder), "README")
        end

        function testFolderTargetUsesContentDispositionName(testCase)
            url = testCase.fileUrl('download', 'filename', 'data-1.0.zip');

            downloadQuietly(testCase.Folder, url);

            testCase.verifyEqual(listFiles(testCase.Folder), "data-1.0.zip")
        end

        function testContentDispositionFoldersAreIgnored(testCase)
            subfolder = fullfile(testCase.Folder, 'sub');
            mkdir(subfolder)
            url = testCase.fileUrl('download', 'filename', '../outside.txt');

            downloadQuietly(subfolder, url);

            testCase.verifyEqual(listFiles(subfolder), "outside.txt")
            testCase.verifyEmpty(listFiles(testCase.Folder))
        end

        function testExistingFileIsReplaced(testCase)
            target = fullfile(testCase.Folder, 'data.txt');
            writeText(target, 'old')

            downloadQuietly(target, testCase.fileUrl('data.txt', 'content', 'new'));

            testCase.verifyEqual(fileread(target), 'new')
        end

        function testRepeatedDownloadToFolderReplacesFile(testCase)
            downloadQuietly(testCase.Folder, testCase.fileUrl('README', 'content', 'first'));

            downloadQuietly(testCase.Folder, testCase.fileUrl('README', 'content', 'second'));

            testCase.verifyEqual(fileread(fullfile(testCase.Folder, 'README')), 'second')
        end

        function testFailedDownloadKeepsExistingFile(testCase)
            target = fullfile(testCase.Folder, 'data.txt');
            writeText(target, 'old')

            testCase.verifyError(@() downloadQuietly(target, testCase.statusUrl(404)), ...
                'webprogress:download:RequestFailed')

            testCase.verifyEqual(fileread(target), 'old')
            testCase.verifyEqual(listFiles(testCase.Folder), "data.txt")
        end

        function testEmptyFileIsSaved(testCase)
            target = fullfile(testCase.Folder, 'empty.txt');

            downloadQuietly(target, testCase.fileUrl('empty.txt', 'content', ''));

            testCase.verifyEqual(listFiles(testCase.Folder), "empty.txt")
            testCase.verifyEmpty(fileread(target))
        end

        function testRelativeTargetReturnsFullPath(testCase)
            testCase.applyFixture( ...
                matlab.unittest.fixtures.CurrentFolderFixture(testCase.Folder));

            savedPath = downloadQuietly('relative.txt', testCase.fileUrl('relative.txt'));

            testCase.verifyTrue(isfile(savedPath))
            testCase.verifyEqual(string(fileparts(char(savedPath))), ...
                string(fileattribName(testCase.Folder)))
        end

        function testMissingFolderErrors(testCase)
            target = fullfile(testCase.Folder, 'missing', 'data.txt');

            testCase.verifyError(@() downloadQuietly(target, testCase.fileUrl('data.txt')), ...
                'webprogress:download:FolderNotFound')
        end

        function testFolderTargetWithoutNameErrors(testCase)
            url = testCase.ServerUrl + "/files/";

            testCase.verifyError(@() downloadQuietly(testCase.Folder, url), ...
                'webprogress:download:NoFilename')

            testCase.verifyEmpty(listFiles(testCase.Folder))
        end
    end

    methods (Access = private)
        function url = fileUrl(testCase, name, varargin)
            %fileUrl - Return the URL of a served text file with query options
            url = testCase.ServerUrl + "/files/" + name;
            if ~isempty(varargin)
                pairs = string(varargin);
                query = strjoin(pairs(1:2:end) + "=" + pairs(2:2:end), "&");
                url = url + "?" + query;
            end
        end

        function url = statusUrl(testCase, statusCode)
            %statusUrl - Return the URL that answers with statusCode
            url = sprintf("%s/%d", testCase.ServerUrl, statusCode);
        end
    end
end

function savedPath = downloadQuietly(target, url)
    %downloadQuietly - Download with Command Window progress that never prints
    savedPath = webprogress.download(target, url, ...
        'DisplayMode', 'Command Window', 'UpdateInterval', 3600);
end

function names = listFiles(folder)
    %listFiles - Return the names of the files in a folder
    listing = dir(folder);
    names = string({listing(~[listing.isdir]).name});
end

function writeText(filePath, text)
    %writeText - Write text to a file, replacing its contents
    fileId = fopen(filePath, 'w');
    fwrite(fileId, text);
    fclose(fileId);
end

function name = fileattribName(folder)
    %fileattribName - Return the full path of a folder as fileattrib gives it
    [~, info] = fileattrib(folder);
    name = info.Name;
end
