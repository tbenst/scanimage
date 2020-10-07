function mFiles = getAllMFiles(folder)
    if nargin < 1 || isempty(folder)
        folder = pwd();
    end
    
    mFiles = recursiveFind(cell(0,1),folder);
    
    function mFiles = recursiveFind(classes,folder)
        s = what(folder);
        packageName = regexpi(folder,'(\+[^\\]+\\)*\+[^\\]+$','match','once');
        packageName = regexprep(packageName,'\\\+','.');
        packageName = regexprep(packageName,'^\+','');
        if ~isempty(packageName)
            packageName = strcat(packageName,'.');
        end
        mfiles = regexpi(s.m,'.*(?=\.m$)','match','once');
        mfiles = strcat(packageName,mfiles);
        classFolders = strcat(packageName,s.classes);

        mFiles = vertcat(classes,mfiles,classFolders);
        for idx = 1:numel(s.packages)
            mFiles = recursiveFind(mFiles,fullfile(folder,['+' s.packages{idx}]));
        end
    end
end

%--------------------------------------------------------------------------%
% getAllMFiles.m                                                           %
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
