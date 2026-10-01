classdef ProgressRecorder < handle
    %ProgressRecorder - Record the progress reports a transfer makes
    %   recorder = ProgressRecorder() records the structs passed to
    %   recorder.record. Pass @recorder.record as ProgressFcn and
    %   @recorder.isCancelRequested as CancelRequestedFcn.
    %
    %   recorder = ProgressRecorder(N) asks for the transfer to stop once
    %   N reports have been recorded. With N = 0 it asks before the first.

    properties (SetAccess = private)
        Reports = struct('ActionName', {}, 'TransferredBytes', {}, 'TotalBytes', {})
        NumCancelChecks = 0 % Number of times isCancelRequested was called
    end

    properties (SetAccess = immutable)
        CancelAfter (1,1) double = Inf % Reports after which to ask for a stop
    end

    methods
        function obj = ProgressRecorder(cancelAfter)
            if nargin > 0
                obj.CancelAfter = cancelAfter;
            end
        end

        function record(obj, progress)
            obj.Reports(end+1) = progress;
        end

        function tf = isCancelRequested(obj)
            obj.NumCancelChecks = obj.NumCancelChecks + 1;
            tf = numel(obj.Reports) >= obj.CancelAfter;
        end
    end
end
