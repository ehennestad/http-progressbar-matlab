classdef ToolboxTest <  matlab.unittest.TestCase
% ToolboxTest - Unit test for testing the toolbox functions.


    methods (Test)
        function testToolboxDir(testCase)
            pathStr = webprogress.toolboxdir();
            testCase.verifyClass(pathStr, 'char')
            testCase.verifyTrue(isfolder(pathStr))
        end

        function testToolboxVersion(testCase)
            versionStr = webprogress.toolboxversion();
            testCase.verifyClass(versionStr, 'char')

            % The version is the number alone, in major.minor.patch form
            % with an optional sub-patch number.
            testCase.verifyMatches(versionStr, '^\d+\.\d+\.\d+(\.\d+)?$')
        end
    end
end
