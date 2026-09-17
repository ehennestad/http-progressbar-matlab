function gettingStarted()
    % GETTINGSTARTED Open the getting started guide for the toolbox
    %
    %   GETTINGSTARTED() opens the getting started guide for the toolbox.
    %
    %   Example:
    %       webprogress.gettingStarted()
    %
    %   See also webprogress.toolboxdir, webprogress.toolboxversion

    % Display welcome message
    fprintf('Welcome to HTTP Progress Bar!\n\n');
    fprintf('Download and upload files over HTTP with a live progress display\n\n');
    
    % Display version information
    fprintf('Version: %s\n', webprogress.toolboxversion());
    
    % Display directory information
    fprintf('Toolbox directory: %s\n\n', webprogress.toolboxdir());
    
    % Display available functions
    fprintf('Available functions:\n');
    fprintf('  - webprogress.toolboxdir\n');
    fprintf('  - webprogress.toolboxversion\n');
    fprintf('  - webprogress.gettingStarted\n\n');
    
    % Display examples
    fprintf('Examples:\n');
    examplesDir = fullfile(webprogress.toolboxdir(), 'code', 'examples');
    if exist(examplesDir, 'dir')
        exampleFiles = dir(fullfile(examplesDir, '*.m'));
        if ~isempty(exampleFiles)
            for i = 1:length(exampleFiles)
                fprintf('  - %s\n', exampleFiles(i).name);
            end
        else
            fprintf('  No examples found.\n');
        end
    else
        fprintf('  Examples directory not found.\n');
    end
    
    % Display documentation
    fprintf('\nDocumentation:\n');
    docsDir = fullfile(webprogress.toolboxdir(), 'docs');
    if exist(docsDir, 'dir')
        fprintf('  Documentation is available in the docs directory:\n');
        fprintf('  %s\n', docsDir);
    else
        fprintf('  Documentation directory not found.\n');
    end
    
    fprintf('\nFor more information, see the README.md file in the toolbox directory.\n');
end
