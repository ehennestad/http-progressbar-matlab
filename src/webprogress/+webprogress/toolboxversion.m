function versionStr = toolboxversion()
    % TOOLBOXVERSION Return the version of the toolbox
    %
    %   VERSION = TOOLBOXVERSION() returns the version of the toolbox as a
    %   character vector in major.minor.patch form, with an optional
    %   sub-patch number, for example '1.2.1'.
    %
    %   Example:
    %       version = webprogress.toolboxversion()
    %
    %   See also webprogress.toolboxdir

    rootPath = fileparts(fileparts(mfilename('fullpath')));
    contentsFile = fullfile(rootPath, 'Contents.m');

    fileStr = fileread(contentsFile);

    % Match major.minor.patch with an optional sub-patch number. The
    % optional part sits inside the named group so that the group always
    % matches when the pattern does.
    versionPattern = 'Version\s+(?<version>\d+\.\d+\.\d+(\.\d+)?)';
    matchedVersion = regexp(fileStr, versionPattern, 'names', 'once');

    if isempty(matchedVersion)
        error('WEBPROGRESS:Version:VersionNotFound', ...
            'No version was detected for this HTTP Progress Bar installation.')
    end
    versionStr = matchedVersion.version;
end
