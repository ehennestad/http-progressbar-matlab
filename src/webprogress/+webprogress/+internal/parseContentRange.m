function [firstByte, lastByte, completeLength] = parseContentRange(response)
%parseContentRange - Return the byte positions in the Content-Range of a response
%   [FIRST, LAST, COMPLETE] = webprogress.internal.parseContentRange(RESPONSE)
%   reads the Content-Range header field of RESPONSE (RFC 9110, section
%   14.4). It has one of two forms:
%       bytes FIRST-LAST/COMPLETE - the bytes of the body, as a 206
%                                   response to a single range carries.
%                                   COMPLETE is "*" when the server does
%                                   not know the length of the file.
%       bytes */COMPLETE          - the length of the file, as a 416
%                                   response carries.
%   Each output is NaN when the field does not give it, or when the field
%   is missing or in another form.
%
%   This function is used by webprogress.download.

%   Written by Eivind Hennestad

    firstByte = nan;
    lastByte = nan;
    completeLength = nan;

    field = response.getFields("Content-Range");
    if isempty(field)
        return
    end

    % The two forms are matched apart, because regexp leaves out the
    % tokens of an alternative that did not match. str2double gives NaN
    % for "*".
    value = char(field(end).Value);
    tokens = regexp(value, '^\s*bytes\s+(\d+)-(\d+)/(\d+|\*)\s*$', 'tokens', 'once');
    if ~isempty(tokens)
        firstByte = str2double(tokens{1});
        lastByte = str2double(tokens{2});
        completeLength = str2double(tokens{3});
        return
    end

    tokens = regexp(value, '^\s*bytes\s+\*/(\d+)\s*$', 'tokens', 'once');
    if ~isempty(tokens)
        completeLength = str2double(tokens{1});
    end
end
