classdef MotorMarker < most.util.Uuid
    properties
        name
    end
    
    properties (SetAccess = immutable)
        hPt
        powers
    end
    
    methods
        function obj = MotorMarker(name,hPt,powers)
            obj.name = name;
            obj.hPt = hPt;
            obj.powers = powers;
        end
        
        function val = get.name(obj)
            if isempty(obj.name)
                val = obj.uuid(1:8);
            else
                val = obj.name;
            end
        end
    end
end

%--------------------------------------------------------------------------%
% MotorMarker.m                                                            %
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
