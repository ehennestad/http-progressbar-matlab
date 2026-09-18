classdef ProgressDisplayTest < matlab.unittest.TestCase
    %ProgressDisplayTest - Tests that a transfer displays its progress
    %   The tests transfer files with a local server. They are skipped when
    %   python3 or a Unix shell is unavailable.

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
        function testShortDownloadShowsProgressAtDefaultInterval(testCase)
            % A download from the local server finishes in well under one
            % second, which is the default UpdateInterval. Two things have
            % to hold for it to report anything: the HTTP stack has to call
            % the monitor at all, which it only does when the monitor caps
            % ProgressMonitor.Interval well below the transfer time, and
            % the monitor has to display the first progress it receives
            % rather than waiting out an update interval first.
            target = fullfile(testCase.Folder, 'data.txt');

            output = captureOutput(@() webprogress.download(target, ...
                testCase.ServerUrl + "/files/data.txt", ...
                'DisplayMode', 'Command Window'));

            testCase.verifySubstring(output, 'Downloaded')
            testCase.verifySubstring(output, 'Completed in')
        end

        function testShortDownloadShowsProgressAtShortInterval(testCase)
            target = fullfile(testCase.Folder, 'data.txt');

            output = captureOutput(@() webprogress.download(target, ...
                testCase.ServerUrl + "/files/data.txt", ...
                'DisplayMode', 'Command Window', 'UpdateInterval', 0.001));

            testCase.verifySubstring(output, 'Downloaded')
            testCase.verifySubstring(output, 'Completed in')
        end

        function testDownloadTitleShowsGivenFilename(testCase)
            target = fullfile(testCase.Folder, 'saved.txt');

            output = captureOutput(@() webprogress.download(target, ...
                testCase.slowFileUrl('data.txt'), ...
                'DisplayMode', 'Command Window', ...
                'Filename', 'folder/object.json'));

            testCase.verifySubstring(output, 'Downloading folder/object.json')
        end

        function testGivenFilenameReplacesNameFromUrl(testCase)
            import matlab.unittest.constraints.ContainsSubstring
            target = fullfile(testCase.Folder, 'saved.txt');

            output = captureOutput(@() webprogress.download(target, ...
                testCase.slowFileUrl('data.txt'), ...
                'DisplayMode', 'Command Window', ...
                'ShowFilename', true, 'Filename', 'object.json'));

            testCase.verifySubstring(output, 'Downloading object.json')
            testCase.verifyThat(output, ~ContainsSubstring('data.txt'))
        end
    end

    methods (Access = private)
        function url = slowFileUrl(testCase, name)
            %slowFileUrl - Return the URL of a served file with a delayed body
            %   The HTTP stack calls a progress monitor only while a
            %   transfer is in progress, first after the 0.01 seconds that
            %   the monitor sets as ProgressMonitor.Interval. A test that
            %   reads the progress title needs that call, so the server
            %   holds the body back for much longer than that.
            bodyDelaySeconds = 0.2;
            url = sprintf("%s/files/%s?delay=%g", ...
                testCase.ServerUrl, name, bodyDelaySeconds);
        end
    end
end

function output = captureOutput(fcn) %#ok<INUSD> fcn is called inside evalc
    %captureOutput - Call a function and return its Command Window output
    output = evalc('fcn()');
end
