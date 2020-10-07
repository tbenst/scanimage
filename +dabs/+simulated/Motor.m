classdef Motor < dabs.interfaces.MotorController
    properties (SetAccess = protected, SetObservable, AbortSet)
        lastKnownPosition = [0 0 0];
        isMoving = false;
        isHomed = true;
        errorMsg = '';
    end
    
    properties (SetAccess=protected)
        numAxes = 3;
    end
    
    properties (SetAccess=private, Hidden)
        hTransition
    end
    
    properties
        velocity_um_per_s = 500;
    end
    
    properties (Hidden,Dependent)
        lastKnownPositionInternal; % lastKnownPosition is SetAccess=protected and can't be modified by most.gui.Transition
    end
    
    %% LIFECYCLE
    methods
        function obj = Motor(name)
            obj = obj@dabs.interfaces.MotorController(name);
            
            obj.reinit();
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hTransition);
        end
    end
    
    %% ABSTRACT METHOD IMPLEMENTATIONS (dabs.interfaces.MotorController)
    methods
        function reinit(obj)
            obj.errorMsg = '';
            obj.stop();
            fprintf('Simulated Stage controller initialized.\n');
            obj.queryPosition();
        end
        
        function tf = queryMoving(obj)
            tf = obj.isMoving;
        end
        
        function v = queryPosition(obj)
            v = obj.lastKnownPosition;
        end
        
        function move(obj,position,timeout_s)
            if nargin < 3 || isempty(timeout_s)
                timeout_s = obj.defaultTimeout_s;
            end
            
            obj.moveAsync(position);
            obj.moveWaitForFinish(timeout_s)
        end
        
        function moveWaitForFinish(obj,timeout_s)
            if nargin < 2 || isempty(timeout_s)
                timeout_s = obj.defaultTimeout_s;
            end
            
            s = tic();
            while toc(s) <= timeout_s
                if obj.isMoving
                    pause(0.01); % still moving
                else
                    return;
                end
            end
            
            obj.stop();
            error('Motor %s: Move timed out.',obj.name); % if we reach this line, the move timed out
        end
        
        %%% local function
        function moveAsync(obj,position,callback)
            if nargin < 3 || isempty(callback)
                callback = [];
            end
            
            assert(~obj.isMoving);
            
            if ~isempty(obj.errorMsg)
                return
            end
            
            % filter NaNs
            position(isnan(position)) = obj.lastKnownPosition(isnan(position));
            
            d = max(abs(obj.lastKnownPosition-position));
            duration = d / obj.velocity_um_per_s;
            trajectory = [];
            
            obj.isMoving = true;
            
            updatePeriod = 0.3;
            obj.hTransition = most.gui.Transition(duration,obj,'lastKnownPositionInternal',position,trajectory,@moveCompleteCallback,updatePeriod);
            
            function moveCompleteCallback(varargin)
                obj.isMoving = false;
                if ~isempty(callback)
                    callback();
                end
            end
        end
        
        function stop(obj)
            most.idioms.safeDeleteObj(obj.hTransition);
            obj.isMoving = false;
        end
        
        function startHoming(obj)
            obj.move([0,0,0]);
            obj.isHomed = true;
        end
    end
    
    %% Property Getter/Setter
    methods
        function set.lastKnownPositionInternal(obj,val)
            obj.lastKnownPosition = val;
        end
        
        function val = get.lastKnownPositionInternal(obj)
            val = obj.lastKnownPosition;
        end
    end
end


%--------------------------------------------------------------------------%
% Motor.m                                                                  %
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
