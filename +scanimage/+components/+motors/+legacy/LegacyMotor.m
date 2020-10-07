classdef LegacyMotor < dabs.interfaces.MotorController & most.HasMachineDataFile
    %%% Abstract property realizations (most.HasMachineDataFile)
    properties (Constant, Hidden)
        %Value-Required properties
        mdfClassName = mfilename('class');
        mdfHeading = 'LegacyMotor';
        
        %Value-Optional properties
        mdfDependsOnClasses; %#ok<MCCPI>
        mdfDirectProp; %#ok<MCCPI>
        mdfPropPrefix; %#ok<MCCPI>
        
        mdfDefault = defaultMdfSection();
    end
    
    properties
        hMotor
    end
    
    properties (Dependent)
        hLSC
    end
    
    %%% dabs.interfaces.MotorController properties
    properties (SetObservable, SetAccess=protected, AbortSet)
        lastKnownPosition;  % [numeric] [1 x numAxes] sized vector with the last known position of all motors
        isMoving;           % [logical] Scalar that is TRUE only if a move initiated by obj.move OR obj.moveAsync has not finished
        isHomed = true;     % [logical] Scalar that is TRUE if the motor's absolute position is known relative to its home position
        errorMsg;           % [char]    Empty string if no error occured. If error occurs, character array specifying the error
    end
    
    properties (SetAccess=protected)
        numAxes;            % [numeric] Scalar integer describing the number of axes of the MotorController
    end
    
    properties (SetAccess = private, GetAccess = private)
        hListeners
    end
    
    %%% LifeCycle
    methods
        function obj = LegacyMotor(name)
            obj = obj@dabs.interfaces.MotorController(name);
            
            custMdfHeading = sprintf('LegacyMotor (%s)',name);
            obj = obj@most.HasMachineDataFile(true, custMdfHeading);
            
            obj.hMotor = scanimage.components.motors.legacy.StageController(obj.mdfData);
            obj.numAxes = obj.hMotor.numDeviceDimensions;
            obj.hListeners = most.ErrorHandler.addCatchingListener(obj.hMotor,'LSCError',@obj.lscErrorUpdate);
            
            obj.queryPosition();
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hMotor);
        end
    end
    
    %%% dabs.interfaces.MotorController
    methods
        function reinit(obj)
            obj.hMotor.reinitMotor();
        end
        
        function tf = queryMoving(obj)
            tf = obj.hMotor.hLSC.isMoving;
        end
        
        function pos = queryPosition(obj)
            pos = obj.hMotor.positionAbsolute;
            obj.lastKnownPosition = pos;
        end
        
        function move(obj,position,timeout_s)
            if nargin > 3 && ~isempty(timeout_s)
                obj.hMotor.moveTimeout = timeout_s;
            end
            
            obj.moveCompleteAbsolute(position);
        end
        
        function moveAsync(obj,position,callback)
            if nargin > 2 && ~isempty(callback)
                error('Motor %s does not support async move with a callback',obj.name);
            end
            obj.hMotor.moveStartAbsolute(position);
        end
        
        function stop(obj)
            obj.moveInterrupt();
        end
        
        function startHoming(obj)
            error('Motor %s does not support homing',obj.name);
        end
    end
    
    methods
        function moveWaitForFinish(obj, timeout_s)
            if nargin < 2 || isempty(timeout_s)
                timeout_s = obj.defaultTimeout_s;
            end
            
            obj.hMotor.moveWaitForFinish(timeout_s);
        end
        
        function lscErrorUpdate(obj,varargin)
            obj.errorMsg = ''; % fire listeners
        end
    end
    
    methods
        function val = get.hLSC(obj)
            val = obj.hMotor.hLSC;
        end
        
        function val = get.isMoving(obj)
            val = obj.initSuccessful && obj.queryMoving();
        end
        
        function val = get.errorMsg(obj)
            if ~most.idioms.isValidObj(obj.hMotor)
                val = obj.errorMsg; % returns error message from init
            elseif obj.hMotor.lscErrPending
                val = sprintf('Motor %s is in an error state',obj.name);
            else
                val = '';
            end
        end
    end
end

function s = defaultMdfSection()
    s = [...
        makeEntry('Motor used for X/Y/Z motion, including stacks.')... % comment only
        makeEntry()... % blank line
        makeEntry('controllerType','','If supplied, one of {''sutter.mp285'', ''sutter.mpc200'', ''thorlabs.mcm3000'', ''thorlabs.mcm5000'', ''scientifica'', ''pi.e665'', ''pi.e816'', ''npoint.lc40x'', ''bruker.MAMC''}.')...
        makeEntry('comPort',[],'Integer identifying COM port for controller, if using serial communication')...
        makeEntry('customArgs',{{}},'Additional arguments to stage controller. Some controller require a valid stageType be specified')...
        makeEntry('invertDim','','string with one character for each dimension specifying if the dimension should be inverted. ''+'' for normal, ''-'' for inverted')...
        makeEntry('positionDeviceUnits',[],'1xN array specifying, in meters, raw units in which motor controller reports position. If unspecified, default positionDeviceUnits for stage/controller type presumed.')...
        makeEntry('velocitySlow',[],'Velocity to use for moves smaller than motorFastMotionThreshold value. If unspecified, default value used for controller. Specified in units appropriate to controller type.')...
        makeEntry('velocityFast',[],'Velocity to use for moves larger than motorFastMotionThreshold value. If unspecified, default value used for controller. Specified in units appropriate to controller type.')...
        makeEntry('moveCompleteDelay',[],'Delay from when stage controller reports move is complete until move is actually considered complete. Allows settling time for motor')...
        makeEntry('moveTimeout',[],'Default: 2s. Fixed time to wait for motor to complete movement before throwing a timeout error')...
        makeEntry('moveTimeoutFactor',[],'(s/um) Time to add to timeout duration based on distance of motor move command')...
        ];
    
    function se = makeEntry(name,value,comment,liveUpdate)
        if nargin == 0
            name = '';
            value = [];
            comment = '';
        elseif nargin == 1
            comment = name;
            name = '';
            value = [];
        elseif nargin == 2
            comment = '';
        end
        
        if nargin < 4
            liveUpdate = false;
        end
        
        se = struct('name',name,'value',value,'comment',comment,'liveUpdate',liveUpdate);
    end
end



%--------------------------------------------------------------------------%
% LegacyMotor.m                                                            %
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
