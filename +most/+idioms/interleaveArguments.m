function args = interleaveArguments(argNames,argVals)    
    assert(iscellstr(argNames),'fieldNames needs to be a cellstring');
    assert(iscell(argVals),'fieldVals needs to be a cell');
    
    argNames = squeeze(argNames);
    argVals = squeeze(argVals);
    
    assert(isequal(size(argNames),size(argVals)),...
        'fieldNames and fieldVals need to have the same size');
    
    if ~isempty(argNames)
        assert(isvector(argNames),'fieldNames and fieldVals need to be cell vectors');
    end
    
    args = reshape([argNames(:)';argVals(:)'],[],1)';
end

%--------------------------------------------------------------------------%
% interleaveArguments.m                                                    %
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
