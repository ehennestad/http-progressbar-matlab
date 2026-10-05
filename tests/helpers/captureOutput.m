function [output, varargout] = captureOutput(fcn) %#ok<INUSD> fcn is called inside evalc
%captureOutput - Call a function and return its Command Window output
%   OUTPUT = captureOutput(FCN) calls FCN with no inputs and returns what
%   it printed to the Command Window, so a test can assert on the
%   printed progress without showing it. An error raised by FCN is
%   passed on to the caller.
%
%   [OUTPUT, OUT1, ..., OUTN] = captureOutput(FCN) also returns the
%   first N outputs of FCN.

    varargout = cell(1, nargout - 1);
    output = evalc("[varargout{1:nargout-1}] = fcn();");
end
