function [functionName,localFunctionName,packageName] = getFunctionInfo(fileName)
    functionName = '';
    packageName = '';
    localFunctionName = '';
    
    if nargin<1 || isempty(fileName)
        stack = dbstack('-completenames');
        if numel(stack) < 2
            return % called from command window
        end
        fileName = stack(2).file;
        localFunctionName = stack(2).name;
    end
    
    [filepath,functionName,~] = fileparts(fileName);
    fsep = regexptranslate('escape',filesep());
    packageName = regexpi(filepath,['(' fsep '\+[^' fsep '\+]*)*$'],'match','once');
    packageName = regexprep(packageName,[fsep '\+'],'.');
    packageName = regexprep(packageName,'^\.','');

    if strcmpi(functionName,localFunctionName)
        localFunctionName = '';
    end
end

%--------------------------------------------------------------------------%
% getFunctionInfo.m                                                        %
% Copyright © 2020 Vidrio Technologies, LLC                                %
%                                                                          %
% ScanImage is licensed under the Apache License, Version 2.0              %
% (the "License"); you may not use any files contained within the          %
% ScanImage release  except in compliance with the License.                %
% You may obtain a copy of the License at                                  %
% http://www.apache.org/licenses/LICENSE-2.0                               %
%                                                                          %
% Unless required by applicable law or agreed to in writing, software      %
% distributed under the License is distributed on an "AS IS" BASIS,        %
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. %
% See the License for the specific language governing permissions and      %
% limitations under the License.                                           %
%--------------------------------------------------------------------------%
