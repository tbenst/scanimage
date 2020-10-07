 classdef EventData < event.EventData
     
    properties
        changeType;
        propertyName;
        oldValue;
        newValue;
        srcObj;
        srcObjParent;
    end
    
    methods
        function obj = EventData(srcObj, changeType, propertyName, oldValue, newValue, srcObjParent)
            obj.changeType = changeType;
            obj.srcObj = srcObj;
            obj.propertyName = propertyName;
            obj.oldValue = oldValue;
            obj.newValue = newValue;
            
            if nargin > 5
                obj.srcObjParent = srcObjParent;
            end
        end
    end
end


%--------------------------------------------------------------------------%
% EventData.m                                                              %
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
