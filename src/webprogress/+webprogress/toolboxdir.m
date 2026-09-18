function rootDir = toolboxdir()
    % TOOLBOXDIR Return the root directory of the toolbox
    %
    %   ROOT_DIR = TOOLBOXDIR() returns the root directory of the toolbox.
    %
    %   Example:
    %       rootDir = webprogress.toolboxdir()
    %
    %   See also webprogress.toolboxversion

    % Get the location of this function
    functionPath = mfilename('fullpath');

    % Get the namespace directory (+webprogress)
    namespaceDir = fileparts(functionPath);

    % Get the toolbox root directory (parent of the namespace directory)
    rootDir = fileparts(namespaceDir);
end
