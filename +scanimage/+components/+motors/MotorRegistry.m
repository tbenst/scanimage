classdef MotorRegistry
    properties (Constant)
        searchPath = fullfile(fileparts(mfilename('fullpath')),'+motorRegistryEntries');
    end
    
    methods (Static)
        function entries = getEntries()
            searchPath = scanimage.components.motors.MotorRegistry.searchPath;
            mFiles = most.util.getAllMFiles(searchPath);
            
            entries = scanimage.components.motors.motorRegistryEntries.Simulated.empty(1,0);
            
            for idx = 1:numel(mFiles)
                mc = meta.class.fromName(mFiles{idx});
                if ~isempty(mc)
                    superClassList = vertcat(mc.SuperclassList.Name);
                    if ismember('scanimage.components.motors.motorRegistryEntries.MotorRegistryEntry',superClassList)
                        constructor = str2func(mFiles{idx});
                        entries(end+1) = constructor();
                    end
                end
            end
        end
        
        function entry = searchEntry(name)
            entries = scanimage.components.motors.MotorRegistry.getEntries();
            
            entry = scanimage.components.motors.motorRegistryEntries.Simulated.empty(1,0);
            
            for idx = 1:numel(entries)
                tf = any(strcmpi(name,entries(idx).displayName));
                tf = tf || any(strcmpi(name,entries(idx).aliases));
                tf = tf || any(strcmpi(name,entries(idx).className));
                
                if tf
                    entry = entries(idx);
                    return
                end
            end
        end
    end
end

%--------------------------------------------------------------------------%
% MotorRegistry.m                                                          %
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
