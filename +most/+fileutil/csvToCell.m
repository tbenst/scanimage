function str = csvToCell(filename, delimiter, delimiterIsRegex)
if nargin < 2 || isempty(delimiter)
    delimiter = ',';
end

if nargin < 3 || isempty(delimiterIsRegex)
    delimiterIsRegex = false;
end

validateattributes(delimiter,{'char'},{'row'});
validateattributes(delimiterIsRegex,{'numeric','logical'},{'scalar','binary'});

if ~delimiterIsRegex
    delimiter = regexptranslate('escape',delimiter);
end

str = readFileContent(filename);

% split into lines
str = regexp(str,'\s*[\r\n]+\s*','split')';
if isempty(str{end})
    str(end) = [];
end

% split at delimiter into cells
delimiter = ['\s*' delimiter '\s*']; % ignore white space characters around delimiter
str = regexp(str,delimiter,'split');
str = vertcat(str{:});
end

function str = readFileContent(filename)
    assert(exist(filename,'file')~=0,'File %s not found',filename);
    hFile = fopen(filename,'r');
    try
        % read entire content of file
        str = fread(hFile,'*char')';
        fclose(hFile);
    catch ME
        % clean up in case of error
        fclose(hFile);
        rethrow(ME);
    end
end

%--------------------------------------------------------------------------%
% csvToCell.m                                                              %
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
