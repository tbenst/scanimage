function safeDeleteObj(objs)
    %SAFEDELETEOBJ Checks if the object handle is valid and deletes it if so.
    % Returns true if object was valid.
    if isempty(objs)
        return
    end
    
    if iscell(objs)
        cellfun(@(obj)safeDelete(obj),objs);
    elseif numel(objs) > 1
        arrayfun(@(obj)safeDelete(obj),objs);
    else
        safeDelete(objs);
    end
end

function safeDelete(obj)
try
    if most.idioms.isValidObj(obj)
        if isa(obj,'timer')
            stop(obj);
        end
        delete(obj);
    end
catch ME
    % No reason to report any error if object isn't extant/valid    
    % most.ErrorHandler.logAndReportError(ME);
end
end


%--------------------------------------------------------------------------%
% safeDeleteObj.m                                                          %
% Copyright � 2020 Vidrio Technologies, LLC                                %
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
