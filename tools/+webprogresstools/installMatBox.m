function installMatBox(mode)
% installMatBox - Install MatBox from latest release or latest commit

%   Todo:
%   - If MatBox release has been updated on remote, should reinstall.

    arguments
        mode (1,1) string {mustBeMember(mode, ["release", "commit"])} = "release"
    end
    
    if mode == "release"
        installFromRelease()    % local function
    elseif mode == "commit"
        installFromCommit()     % local function
    end
end

function installFromRelease()
    addonsTable = matlab.addons.installedAddons();
    isMatchedAddon = addonsTable.Name == "MatBox";
    
    if ~isempty(isMatchedAddon) && any(isMatchedAddon)
        matlab.addons.enableAddon('MatBox')
    else
        info = webread('https://api.github.com/repos/ehennestad/MatBox/releases/latest');
        assetNames = {info.assets.name};
        isMltbx = startsWith(assetNames, 'MatBox') & endsWith(assetNames, '.mltbx');

        % A release can carry several assets. Take the first toolbox file
        % instead of indexing with the whole mask, which would expand to a
        % comma-separated list as soon as more than one asset matches.
        matchedAssets = info.assets(isMltbx);
        if isempty(matchedAssets)
            error('webprogress:tools:MatBoxAssetNotFound', ...
                ['The latest MatBox release has no .mltbx asset. ', ...
                'Install MatBox manually or use the "commit" mode.'])
        end

        % Download matbox
        tempFilePath = websave(tempname, matchedAssets(1).browser_download_url);
        cleanupObj = onCleanup(@() delete(tempFilePath));
        
        % Install toolbox
        matlab.addons.install(tempFilePath);
    end
end


function installFromCommit()
    % Download latest zipped version of repo
    url = "https://github.com/ehennestad/MatBox/archive/refs/heads/main.zip";
    tempFilePath = websave(tempname, url);
    cleanupObj = onCleanup(@() delete(tempFilePath));
    
    % Unzip in temporary location
    unzippedFiles = unzip(tempFilePath, tempdir);
    unzippedFolder = unzippedFiles{1};
    if endsWith(unzippedFolder, filesep)
        unzippedFolder = unzippedFolder(1:end-1);
    end
    
    % Move to installation location
    [~, repoFolderName] = fileparts(unzippedFolder);
    targetFolder = fullfile(userpath, "Add-Ons");
    targetFolder = fullfile(targetFolder, repoFolderName);
    if isfolder(targetFolder); rmdir(targetFolder, "s"); end
    movefile(unzippedFolder, targetFolder);

    % Add to MATLAB's search path
    addpath(genpath(targetFolder))
end