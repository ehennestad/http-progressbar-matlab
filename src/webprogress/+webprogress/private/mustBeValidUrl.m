function mustBeValidUrl(url)
    % Parse the URL the same way download and upload do. The scheme is
    % compared case-sensitively because matlab.net.http rejects an
    % uppercase scheme such as HTTPS with MATLAB:http:UnsupportedScheme.
    uri = matlab.net.URI(url, 'literal');

    isHttpScheme = isscalar(uri.Scheme) && any(strcmp(uri.Scheme, ["http", "https"]));
    if ~isHttpScheme || isempty(uri.Host)
        error("webprogress:validators:InvalidUrl", ...
            "URL must start with http:// or https:// followed by a host name.")
    end
end
