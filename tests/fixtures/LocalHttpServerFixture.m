classdef LocalHttpServerFixture < matlab.unittest.fixtures.Fixture
    %LocalHttpServerFixture - Fixture that runs a local HTTP status server
    %   The fixture starts http_status_server.py with python3 on a free
    %   port of 127.0.0.1. A request to BaseUrl + "/CODE" receives HTTP
    %   status CODE, and a GET request to BaseUrl + "/files/NAME" receives
    %   a text file. The server script describes the query options. The
    %   fixture needs python3 and a Unix shell.

    properties (SetAccess = private)
        BaseUrl string = "" % Server address, such as "http://127.0.0.1:50123"
    end

    properties (Constant, Access = private)
        StartupTimeoutSeconds = 10
    end

    methods
        function setup(fixture)
            %SETUP - Start the server and wait until it reports its port
            serverScript = fullfile(fileparts(mfilename('fullpath')), ...
                'http_status_server.py');
            portFile = [tempname, '.port'];

            % Start the server in the background and print its process ID.
            command = sprintf('python3 "%s" "%s" > /dev/null 2>&1 & echo $!', ...
                serverScript, portFile);
            [status, output] = system(command);
            if status ~= 0
                error('webprogress:test:ServerNotStarted', ...
                    'Could not start the local HTTP server: %s', output)
            end

            processId = str2double(strtrim(output));
            fixture.addTeardown(@() stopServer(processId, portFile))

            port = waitForPort(portFile, fixture.StartupTimeoutSeconds);
            fixture.BaseUrl = sprintf("http://127.0.0.1:%d", port);
        end
    end
end

function port = waitForPort(portFile, timeoutSeconds)
    %waitForPort - Read the port number once the server has written it
    startTime = tic;
    while ~isfile(portFile)
        if toc(startTime) > timeoutSeconds
            error('webprogress:test:ServerTimeout', ...
                'The local HTTP server did not start within %d seconds.', ...
                timeoutSeconds)
        end
        pause(0.05)
    end
    port = str2double(fileread(portFile));
end

function stopServer(processId, portFile)
    %stopServer - Stop the server process and remove its port file
    [~, ~] = system(sprintf('kill %d', processId));
    if isfile(portFile)
        delete(portFile)
    end
end
