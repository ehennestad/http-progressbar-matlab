classdef ResumableFileConsumer < matlab.net.http.io.FileConsumer
%ResumableFileConsumer - Write a response body to a partial file that can be resumed
%   consumer = webprogress.internal.ResumableFileConsumer(PARTFILE,
%   STATEFILE, OFFSET) writes the body of a response to PARTFILE. OFFSET
%   is the start of the byte range that the request asked for, or 0 for a
%   request without a Range header. The file consumer appends the body
%   to PARTFILE, and the response status decides what happens first:
%       206 - The body is appended to PARTFILE when the Content-Range of
%             the response starts at OFFSET and the body has no content
%             coding. Otherwise the consumer raises an error, which ends
%             the transfer before the body is received.
%       200 - PARTFILE is replaced by the body, and STATEFILE is written
%             with the validator and length of the new response.
%   A response with any other status leaves both files unchanged, and
%   its body goes to the response message as without a consumer.
%
%   After the response, ExpectedBytes is the size PARTFILE has when the
%   whole body arrived, and TotalBytes is the length of the complete
%   file. Each is NaN when the response does not give it.
%
%   STATEFILE holds the strong validator of the file, as ETag or
%   Last-Modified, and its total length. It never holds the URL, which
%   for a presigned URL carries a signature.
%
%   This class is used by webprogress.download.

%   Written by Eivind Hennestad

    properties (SetAccess = immutable)
        PartFilePath  string % File that receives the body
        StateFilePath string % File that holds the validator and total length
        RequestedOffset (1,1) double % Start of the requested byte range
    end

    properties (SetAccess = private)
        WriteOffset (1,1) double = 0     % Size of the partial file the body is written after
        ExpectedBytes (1,1) double = nan % Size of the partial file after the whole body
        TotalBytes (1,1) double = nan    % Length of the complete file
    end

    properties
        % Progress monitor of the transfer. Its StartBytes is set to
        % WriteOffset when the response arrives.
        ProgressMonitor = []
    end

    methods
        function obj = ResumableFileConsumer(partFilePath, stateFilePath, requestedOffset)
            arguments
                partFilePath    (1,1) string
                stateFilePath   (1,1) string
                requestedOffset (1,1) double {mustBeNonnegative, mustBeInteger}
            end
            % Permission 'a' appends to an existing file, and initialize
            % empties the file first when the body replaces it.
            obj@matlab.net.http.io.FileConsumer(char(partFilePath), 'a');
            obj.PartFilePath = partFilePath;
            obj.StateFilePath = stateFilePath;
            obj.RequestedOffset = requestedOffset;
        end
    end

    methods (Access = protected)
        function ok = initialize(obj)
        %initialize - Accept the body of a 200 or a matching 206 response
        %   MATLAB calls initialize when the response header arrives, and
        %   sends the body to putData only when it returns true. The file
        %   consumer accepts a body whatever the status, so its decision
        %   counts only for a status whose body belongs in the file.
            response = obj.Response;
            statusCode = double(response.StatusCode);
            ok = false;

            if statusCode == 206
                % A 206 response to a single range carries Content-Range
                % (RFC 9110, section 15.3.7). The body cannot be appended
                % when it starts elsewhere than the partial file ends. An
                % error here ends the transfer, so the body is not
                % received into memory as a refused body would be.
                [firstByte, lastByte, completeLength] = ...
                    webprogress.internal.parseContentRange(response);
                if firstByte ~= obj.RequestedOffset
                    obj.raiseUnexpectedRange(sprintf( ...
                        "The server sent the file from byte %d instead of byte %d.", ...
                        firstByte, obj.RequestedOffset))
                end
                % A byte range applies to the representation as it is
                % sent, after any content coding (RFC 9110, sections 8.4
                % and 14.1). A decoded body cannot be appended at an
                % offset counted in encoded bytes.
                if ~webprogress.internal.hasIdentityEncoding(response)
                    obj.raiseUnexpectedRange("The server sent the part of the file " + ...
                        "in a compressed form, which cannot be appended to the partial file.")
                end
                obj.WriteOffset = obj.RequestedOffset;
                obj.ExpectedBytes = lastByte + 1;
                obj.TotalBytes = completeLength;
                ok = initialize@matlab.net.http.io.FileConsumer(obj);

            elseif statusCode == 200
                % Content-Length counts the bytes as sent, so it is the
                % file size only for a body without a content coding.
                totalBytes = nan;
                if webprogress.internal.hasIdentityEncoding(response)
                    totalBytes = webprogress.internal.getDeclaredLength(response);
                end
                % Replace the partial file before the state file, so that
                % an interruption between the two never pairs old data
                % with the validator of a new file.
                fclose(openFile(obj.PartFilePath, 'w'));
                obj.WriteOffset = 0;
                obj.ExpectedBytes = totalBytes;
                obj.TotalBytes = totalBytes;
                obj.writeState(response)
                ok = initialize@matlab.net.http.io.FileConsumer(obj);
            end

            monitor = obj.ProgressMonitor;
            if ok && ~isempty(monitor) && isvalid(monitor)
                monitor.StartBytes = obj.WriteOffset;
            end
        end
    end

    methods (Access = private)
        function raiseUnexpectedRange(obj, reason)
        %raiseUnexpectedRange - Raise the error for a 206 response that cannot be appended
            error("webprogress:download:UnexpectedRange", ...
                "Cannot resume the download. %s The partial file ""%s"" was left " + ...
                "unchanged. Delete it to download the file from the beginning.", ...
                reason, obj.PartFilePath)
        end

        function writeState(obj, response)
        %writeState - Save the validator and length of a 200 response
        %   Without a strong validator, or for a body that was decoded
        %   from a content coding, the partial file cannot be resumed, so
        %   no state file is kept.
            validator = "";
            if webprogress.internal.hasIdentityEncoding(response)
                validator = getStrongValidator(response);
            end

            if strlength(validator) == 0
                if isfile(obj.StateFilePath)
                    delete(obj.StateFilePath)
                end
                return
            end

            state = struct('Validator', validator, 'TotalBytes', obj.TotalBytes);
            fileId = openFile(obj.StateFilePath, 'w');
            fileCleanup = onCleanup(@() fclose(fileId));
            fwrite(fileId, jsonencode(state), 'char');
        end
    end
end

function fileId = openFile(filePath, permission)
    %openFile - Open a file and raise an error if it cannot be opened
    [fileId, message] = fopen(filePath, permission);
    if fileId < 0
        error("webprogress:download:CannotSaveFile", ...
            "Cannot write the downloaded data to ""%s"": %s", filePath, message)
    end
end

function validator = getStrongValidator(response)
    %getStrongValidator - Return a validator that If-Range can carry, or ""
    %   If-Range needs a strong validator (RFC 9110, section 13.1.5). An
    %   entity tag is weak when it starts with "W/" (section 8.8.3). A
    %   Last-Modified date is used only without an entity tag, and only
    %   when it is strong: at least one second before the Date of the
    %   response (section 8.8.2.2).
    validator = "";

    tagField = response.getFields("ETag");
    if ~isempty(tagField)
        entityTag = strtrim(string(tagField(end).Value));
        if ~startsWith(entityTag, "W/")
            validator = entityTag;
        end
        return
    end

    modifiedField = response.getFields("Last-Modified");
    dateField = response.getFields("Date");
    if isempty(modifiedField) || isempty(dateField)
        return
    end
    lastModified = strtrim(string(modifiedField(end).Value));
    modifiedTime = parseHttpDate(lastModified);
    responseTime = parseHttpDate(strtrim(string(dateField(end).Value)));
    if seconds(responseTime - modifiedTime) >= 1
        validator = lastModified;
    end
end

function time = parseHttpDate(text)
    %parseHttpDate - Convert an IMF-fixdate such as "Sun, 06 Nov 1994 08:49:37 GMT"
    %   Senders must generate this format (RFC 9110, section 5.6.7). Text
    %   in another format gives NaT, which fails every comparison.
    try
        time = datetime(text, 'InputFormat', 'eee, dd MMM yyyy HH:mm:ss ''GMT''', ...
            'Locale', 'en_US', 'TimeZone', 'UTC');
    catch
        time = NaT('TimeZone', 'UTC');
    end
end
