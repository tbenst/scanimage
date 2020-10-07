classdef Singleton < handle
    % Class that implements Singleton behavior
    % inherit from Singleton and call Singleton constructor
    properties (Hidden)
        qualified = false;
    end
    
    methods (Access = protected)
        function obj = Singleton(varargin)
            obj = singleton(obj,true);
            if ~obj.qualified
                obj.singletonConstructor(varargin{:});
                obj.qualified = true;
            end
        end
        
        function delete(obj)
            singleton(obj,false);
        end
    end
    
    methods
        singletonConstructor(obj);
    end
end

%%% local function
function obj = singleton(obj,created)
    % Notes: isvalid is a slow function. instead of checking if object is
    % valid we explicitly remove the object from the storage
    
    persistent classStorage
    persistent objectStorage

    className = class(obj);
    mask = strcmp(className,classStorage);
    stored = any(mask);

    if created
        if stored
            % don't need to explicitly delete new object,
            % Matlab garbage collector will take care of that
            obj = objectStorage{mask};
        else
            classStorage{end+1} = className;
            objectStorage{end+1} = obj;
        end
    else
        if stored && obj.qualified
            classStorage(mask) = [];
            objectStorage(mask) = [];
        end
    end
end

%--------------------------------------------------------------------------%
% Singleton.m                                                              %
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
