classdef (Sealed) TransferCallbackSpy < handle
    %TransferCallbackSpy - Test spy for the ProgressFcn and CancelRequestedFcn of a transfer
    %   spy = TransferCallbackSpy() records the structs passed to
    %   spy.record. Pass @spy.record as ProgressFcn and
    %   @spy.isCancelRequested as CancelRequestedFcn.
    %
    %   spy = TransferCallbackSpy(N) asks for the transfer to stop once
    %   N reports have been recorded. With N = 0 it asks before the first.

    properties (SetAccess = private)
        Reports = struct('ActionName', {}, 'TransferredBytes', {}, 'TotalBytes', {})
        NumCancelChecks = 0 % Number of times isCancelRequested was called
    end

    properties (SetAccess = immutable)
        CancelAfter (1,1) double = Inf % Reports after which to ask for a stop
    end

    methods
        function obj = TransferCallbackSpy(cancelAfter)
            arguments
                cancelAfter (1,1) double {mustBeNonnegative} = Inf
            end
            obj.CancelAfter = cancelAfter;
        end

        function record(obj, progress)
            %record - Record one progress report
            obj.Reports(end+1) = progress;
        end

        function tf = isCancelRequested(obj)
            %isCancelRequested - Return true once CancelAfter reports are recorded
            obj.NumCancelChecks = obj.NumCancelChecks + 1;
            tf = numel(obj.Reports) >= obj.CancelAfter;
        end
    end
end
