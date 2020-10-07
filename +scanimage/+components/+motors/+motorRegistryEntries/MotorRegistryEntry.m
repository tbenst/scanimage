classdef MotorRegistryEntry < matlab.mixin.Heterogeneous
    properties (Abstract)
        displayName; % display name for the motor. e.g. 'Thorlabs MCM3000'
        aliases;     % cell array of names e.g. {'mcm3000','thorlabs.mcm3000'}
        className;   % motor class name e.g. dabs.thorlabs.mcm3000
    end
    
    properties (Dependent)
        metaClass
        mdfHeading
    end
    
    methods
        function hMotor = construct(obj,varargin)
            constructor = obj.getConstructor();
            hMotor = constructor(varargin{:});
        end
        
        function fcnHdl = getConstructor(obj)
            fcnHdl = str2func(obj.className);
        end
    end
    
    methods
        function val = get.metaClass(obj)
            val = meta.class.fromName(obj.className);
        end
        
        function val = get.mdfHeading(obj)
            val = '';
            hasMDF = ismember('most.HasMachineDataFile',{obj.metaClass.SuperclassList.Name});
            if hasMDF
                val = eval([obj.className '.mdfHeading']);
            end
        end
    end
end

%--------------------------------------------------------------------------%
% MotorRegistryEntry.m                                                     %
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
