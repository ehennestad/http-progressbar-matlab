function strLocalFilename = download(strLocalFilename, strURLFilename, options)
%download - Download a file from the web and display progress
%   webprogress.download(FILENAME,URL) downloads the file at URL and
%   saves it to FILENAME. If FILENAME is a folder, the file is saved in
%   that folder. Progress is shown in a waitbar. Percent-encoded
%   characters in URL, such as %20, are sent unchanged.
%
%   FILEPATH = webprogress.download(FILENAME,URL) also returns the full
%   path of the saved file.
%
%   [...] = webprogress.download(...,DisplayMode=MODE) specifies where
%   progress is shown. MODE must be:
%       "Dialog Box"     - (default) Shows progress in a dialog box.
%       "Command Window" - Prints progress in the Command Window.
%
%   [...] = webprogress.download(...,UpdateInterval=SECONDS) specifies
%   the minimum number of seconds between progress updates. The default
%   is 1.
%
%   [...] = webprogress.download(...,ShowFilename=SHOW) shows the file
%   name from URL in the progress title when SHOW is true. The default
%   is false.
%
%   [...] = webprogress.download(...,IndentSize=N) indents progress
%   printed in the Command Window by N spaces. The default is 0.
%
%   [...] = webprogress.download(...,Figure=FIG) shows progress in a
%   uiprogressdlg in the figure FIG. Before R2025a, FIG must be a
%   uifigure. For other figures, progress is shown in a waitbar.
%
%   [...] = webprogress.download(...,FileSizeBytes=N) specifies the file
%   size in bytes to use for progress when the server does not report it.
%
%   webprogress.download raises an error if the server responds with a
%   status that is not a successful 2xx status, and deletes the file
%   written for that response.
%
%   Example: Download a file and print progress in the Command Window
%       url = "https://allen-brain-observatory.s3.us-west-2" + ...
%           ".amazonaws.com/visual-coding-2p/stimulus_mappings.json";
%       filePath = webprogress.download(tempdir, url, ...
%           "DisplayMode", "Command Window");
%
%   See also webprogress.upload, websave

%   Written by Eivind Hennestad

    arguments
        strLocalFilename       char         {mustBeNonempty}
        strURLFilename         char         {mustBeValidUrl}
        options.DisplayMode    char         {mustBeValidDisplay} = 'Dialog Box'
        options.UpdateInterval (1,1) double {mustBePositive}     = 1
        options.ShowFilename   (1,1) logical                     = false
        options.IndentSize     (1,1) uint8                       = 0
        options.Figure         {mustBeFigureOrEmpty}             = []
        options.FileSizeBytes  (1,1) double                      = nan
    end

    % The URL is already percent-encoded, as any URL handed out by a web
    % service is. Without 'literal' the URI constructor would encode it a
    % second time ("%20" would become "%2520") and the server would
    % reject every name with a space or other encoded character.
    uri = matlab.net.URI(strURLFilename, 'literal');

    if options.ShowFilename && ~isempty(uri.Path)
        % URI.Path holds the decoded path segments and excludes the query,
        % which for a signed URL carries the signature.
        filename = char(uri.Path(end));
    else
        filename = '';
    end

    monitorOpts = {...
        'DisplayMode', options.DisplayMode, ...
        'UpdateInterval', options.UpdateInterval, ...
        'Filename', filename, ...
        'IndentSize', options.IndentSize, ...
        'Figure', options.Figure, ...
        'FileSizeBytes', options.FileSizeBytes };
    
    webOpts = matlab.net.http.HTTPOptions(...
        'ProgressMonitorFcn', @(opts) webprogress.FileTransferProgressMonitor(monitorOpts{:}),...
        'UseProgressMonitor', true, ...
        'ConnectTimeout', 20);

    % Create a file consumer for saving the file
    consumer = matlab.net.http.io.FileConsumer(strLocalFilename);
    
    method = matlab.net.http.RequestMethod.GET;
    req = matlab.net.http.RequestMessage(method, [], []);
    
    [resp, ~, ~] = req.send(uri, webOpts, consumer);

    % The file consumer writes the response body whatever the status, so a
    % failed request leaves the server's error page at the target path.
    % Body.Data holds the path that was written, which differs from the
    % input when the input is a folder.
    if resp.StatusCode.getClass() ~= matlab.net.http.StatusClass.Successful
        if ~isempty(resp.Body) && ~isempty(resp.Body.Data) && isfile(resp.Body.Data)
            delete(resp.Body.Data)
        end
        error("webprogress:download:RequestFailed", ...
            "Download failed because the server responded with ""%s"". " + ...
            "Check that the URL is correct and has not expired.", ...
            string(resp.StatusLine))
    end

    strLocalFilename = resp.Body.Data;

    if nargout < 1
        clear strLocalFilename
    end
end
