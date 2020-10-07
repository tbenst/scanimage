classdef MotorController < handle
    % Interface class to communicate with a MotorController
    %
    % preferred units are micrometer for linear axes
    % or degree for rotation axes
    
    properties
        name = '';            % [char] a unique name for the motor
        defaultTimeout_s = 10 % [numeric] scalar that defines the default timeout for a blocking move in seconds
        initSuccessful;
    end
    
    properties (Abstract, SetObservable, SetAccess=protected, AbortSet)
        lastKnownPosition;  % [numeric] [1 x numAxes] sized vector with the last known position of all motors
        isMoving;           % [logical] Scalar that is TRUE only if a move initiated by obj.move OR obj.moveAsync has not finished
        isHomed;            % [logical] Scalar that is TRUE if the motor's absolute position is known relative to its home position
        errorMsg;           % [char]    Empty string if no error occured. If error occurs, character array specifying the error
    end
    
    properties (Abstract, SetAccess=protected)
        numAxes;            % [numeric] Scalar integer describing the number of axes of the MotorController
    end
    
    methods
        function obj = MotorController(name)
            validateattributes(name,{'char'},{'row'});
            obj.name = name;
        end
    end
    
    methods (Abstract)
        % constructor
        % construct object and attempt to init motor. contructor should return successfully even if
        % communication with motor failed. gracefully clean up in the case of failure and set 
        % errorMsg nonempty so that connection can be reattempted by calling reinit.
        
        % reinit
        % reinitializes the communication interface to the motor controller. Should throw if init
        % fails
        reinit(obj);
        
        % queryMoving
        % queries the controller. if any motor axis is moving, returns true.
        % if all axes are idle, returns false. also updates isMoving
        %
        % returns
        %   tf: [logical scalar] TRUE if any axis is moving, FALSE if all
        %                        axes are idle
        tf = queryMoving(obj);
        
        % queryPosition
        % queries all axis positions and returns a [1 x numAxes] containing
        % the axes positions. also updates lastKnownPosition
        %
        % returns
        %   position: [1 x numAxes] sized numeric vector containing the
        %             current positions of all axes
        position = queryPosition(obj);
        
        % move(position,timeout)
        % moves the axes to the specified position. blocks until the move
        % is completed. should be interruptible by UI callbacks for
        % stopping. throws if a move is already in progress
        %
        % parameters
        %   position: [1 x numAxes] sized numeric vector containing the target
        %             positions for all axes. Vector can contain NaNs to
        %             indicate axes that shall not be moved
        %   timeout_s: [numeric,scalar] (optional) if not specified, the default timeout should be used
        move(obj,position,timeout_s);
        
        % moveAsync(position,callback,timeout)
        % initiates a move but returns immediately, not waiting for the move to complete
        % throws if a move is already in progress
        %
        % parameters
        %   position: a [1 x numAxes] sized vector containing the target
        %             positions for all axes. Vector can contain NaNs to
        %             indicate axes that shall not be moved
        %   callback:  [function handle] function to be called when the
        %              move completes
        moveAsync(obj,position,callback);
        
        % moveWaitForFinish(timeout_s)
        % waits until isMoving == false
        %
        % parameters
        %   timeout_s: [numeric,scalar] (optional) if not specified, the default timeout should be used
        %              after the timeout expires, stop() is called
        moveWaitForFinish(obj,timeout_s)
        
        % stop
        % stops the movement of all axes
        stop(obj);
        
        % startHoming()
        % starts the motor's homing routine. Blocks until the homing
        % routine completes. throws if motor does not support homing
        startHoming(obj);
    end
    
    methods
        function set.defaultTimeout_s(obj,val)
            validateattributes(val,{'numeric'},{'scalar','positive','nonnan','real'});
            obj.defaultTimeout_s = val;
        end
        
        function v = get.initSuccessful(obj)
            v = isempty(obj.errorMsg);
        end
    end
end


%--------------------------------------------------------------------------%
% MotorController.m                                                        %
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
