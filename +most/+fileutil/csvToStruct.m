function data = csvToStruct(filename,delimiter,delimiterIsRegex)
    % parses a csv file with a header into a struct
    
    if nargin < 2 || isempty(delimiter)
        delimiter = ',';
    end

    if nargin < 3 || isempty(delimiterIsRegex)
        delimiterIsRegex = false;
    end

    % read the csv file
    csvCell = most.fileutil.csvToCell(filename,delimiter,delimiterIsRegex);
    
    % parse the csv header
    headers = csvCell(1,:);
    headers = cellfun(@(h)str2ValidName(h),headers,'UniformOutput',false);
    
    % parse the csv values
    values = csvCell(2:end,:);
    numericMask = regexpi(values,'^[\d\.+-]+$');
    numericMask = cellfun(@(c)~isempty(c),numericMask);
    matMask = regexpi(values,'^\[.*\]$');
    matMask = cellfun(@(c)~isempty(c),matMask);
    nanMask = strcmpi(values,'NaN');
    
    values(numericMask) = cellfun(@(v)sscanf(v,'%f',1),values(numericMask),'UniformOutput',false);
    values(matMask) = cellfun(@(v)str2num(v),values(matMask),'UniformOutput',false);
    values(nanMask) = {NaN};
    
    %convert into struct array
    values = mat2cell(values,size(values,1),ones(1,size(values,2)));
    structDef = vertcat(headers(:)',values(:)');
    data = struct(structDef{:});
end

function strOut = str2ValidName(strIn)
    strOut = regexprep(strIn,'[^\w\d]',''); % remove all invalid characters
    strOut = regexprep(strOut,'^[\d_]*',''); % remove numeric characters and underscore from front of name
    assert(~isempty(strOut),'Invalid header name: %s',strIn);
end



%--------------------------------------------------------------------------%
% csvToStruct.m                                                            %
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
