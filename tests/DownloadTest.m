classdef DownloadTest < matlab.unittest.TestCase
    %DownloadTest - Tests for webprogress.download
    %   Tests tagged Online download files from the public Allen Brain
    %   Observatory bucket on Amazon S3.

    properties (Constant)
        BaseUrl = "https://allen-brain-observatory.s3.us-west-2.amazonaws.com/visual-coding-2p/"
        SmallFileName = "stimulus_mappings.json"      % About 18 KB
    end

    properties
        TemporaryFolder % Empty folder that is deleted after each test
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            sourceFolder = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                'src', 'webprogress');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(sourceFolder));
        end
    end

    methods (TestMethodSetup)
        function createTemporaryFolder(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.TemporaryFolder = fixture.Folder;
        end
    end

    methods (Test)
        function testInvalidUrlErrors(testCase)
            filePath = fullfile(testCase.TemporaryFolder, 'data.json');

            testCase.verifyError(@() webprogress.download(filePath, 'not a url'), ...
                'webprogress:validators:InvalidUrl')
        end

        function testUppercaseSchemeErrors(testCase)
            filePath = fullfile(testCase.TemporaryFolder, 'data.json');

            testCase.verifyError( ...
                @() webprogress.download(filePath, 'HTTPS://example.com/data.json'), ...
                'webprogress:validators:InvalidUrl')
        end
    end

    methods (Test, TestTags = {'Online'})
        function testDownloadSavesFile(testCase)
            filePath = fullfile(testCase.TemporaryFolder, 'data.json');

            savedPath = webprogress.download(filePath, ...
                testCase.BaseUrl + testCase.SmallFileName, ...
                'DisplayMode', 'Command Window');

            testCase.verifyTrue(isfile(filePath))
            testCase.verifyTrue(isfile(savedPath))
        end

        function testDownloadToFolderUsesNameFromUrl(testCase)
            webprogress.download(testCase.TemporaryFolder, ...
                testCase.BaseUrl + testCase.SmallFileName, ...
                'DisplayMode', 'Command Window');

            expectedPath = fullfile(testCase.TemporaryFolder, testCase.SmallFileName);
            testCase.verifyTrue(isfile(expectedPath))
        end

        function testFailedRequestErrorsAndLeavesNoFile(testCase)
            filePath = fullfile(testCase.TemporaryFolder, 'missing.json');
            url = testCase.BaseUrl + "this_key_does_not_exist.json";

            testCase.verifyError( ...
                @() webprogress.download(filePath, url, 'DisplayMode', 'Command Window'), ...
                'webprogress:download:RequestFailed')

            testCase.verifyFalse(isfile(filePath))
        end
    end
end
