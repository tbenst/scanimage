classdef MPC200_Async < dabs.interfaces.MotorController & most.HasMachineDataFile
    properties (SetObservable, SetAccess=protected, AbortSet)
        lastKnownPosition;      % [numeric] [1 x numAxes] sized vector with the last known position of all motors
        isMoving = false;       % [logical] Scalar that is TRUE only if a move initiated by obj.move OR obj.moveAsync has not finished
        isHomed = true;        % [logical] Scalar that is TRUE if the motor's absolute position is known relative to its home position
        errorMsg = '';          % [char]    that is TRUE if the motor is in an error state and needs to be reinitted
    end
    
    properties (SetAccess=protected)
        numAxes = 3;
        comPort;
    end
        
    properties (SetAccess=private, Hidden)
        hAsyncSerialQueue;
        hPositionTimer;
    end
    
    %%% Abstract property realizations (most.HasMachineDataFile)
    properties (Constant, Hidden)
        %Value-Required properties
        mdfClassName = mfilename('class');
        mdfHeading = 'MPC200';
        
        %Value-Optional properties
        mdfDependsOnClasses; %#ok<MCCPI>
        mdfDirectProp; %#ok<MCCPI>
        mdfPropPrefix; %#ok<MCCPI>
        
        mdfDefault = defaultMdfSection();
    end
    
    %% Lifecycle
    methods
        function obj = MPC200_Async(name)
            obj = obj@dabs.interfaces.MotorController(name);
            
            custMdfHeading = sprintf('MPC200 (%s)',name);
            obj = obj@most.HasMachineDataFile(true, custMdfHeading);
            
            comPort_ = obj.mdfData.comPort;
            validateattributes(comPort_,{'numeric'},{'scalar','integer','positive'});
            obj.comPort = comPort_;
            
            try
                obj.reinit();
            catch ME
                most.ErrorHandler.logAndReportError(ME,['MPC200 failed to initialize. Error: ' ME.message]);
            end
        end
        
        
        function delete(obj)
            try
                obj.stop();
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
            
            most.idioms.safeDeleteObj(obj.hPositionTimer);
            most.idioms.safeDeleteObj(obj.hAsyncSerialQueue);
        end
    end
    
    %% ABSTRACT METHOD IMPLEMENTATIONS (dabs.interfaces.MotorController)
    methods
        function reinit(obj)
            try
                if most.idioms.isValidObj(obj.hPositionTimer)
                    stop(obj.hPositionTimer);
                end
                wasInitialized = ~isempty(obj.hAsyncSerialQueue);
                most.idioms.safeDeleteObj(obj.hPositionTimer);
                most.idioms.safeDeleteObj(obj.hAsyncSerialQueue);
                obj.hAsyncSerialQueue = [];
                
                if wasInitialized
                    pause(0.5); % after closing com port, wait befor reopening, otherwise it can fail
                    
                    calibrateQueryMessage =...
                        'Calibrate device?  This is useful for solving EOT issues.';
                    motorMoveWarningMessage =...
                        ['Warning!  This will move all axes to the start of '...
                        'their respective travel positions.'];
                    calibrationMessage = sprintf('%s\n%s',...
                        calibrateQueryMessage,...
                        motorMoveWarningMessage);
                    dialogTitle = 'MPC-200 Calibration';
                    buttons = {'Yes', 'No'};
                    defaultButton = 'No';
                    choice = questdlg(calibrationMessage,...
                        dialogTitle, buttons{:}, defaultButton);

                    switch choice
                        case 'Yes'
                            obj.calibrate();
                        otherwise
                    end
                end
                
                comport_str = sprintf('COM%d', obj.comPort);
                obj.hAsyncSerialQueue = dabs.generic.AsyncSerialQueue(comport_str,'BaudRate',128000);
                obj.hAsyncSerialQueue.ErrorFcn = @obj.errorFcn;
                
                obj.hPositionTimer = timer('Name','MPC200 position query timer',...
                    'ExecutionMode','fixedRate',...
                    'Period',0.3,...
                    'TimerFcn',@obj.positionTimerFcn);
                
                obj.stop();
                obj.setRoeMode(1);
                
                start(obj.hPositionTimer);
                
                obj.errorMsg = '';
                
                info = obj.infoHardware();
                fprintf('MPC200 Stage controller initialized: %s\n',info);
            catch ME
                obj.errorMsg = ME.message;
                rethrow(ME);
            end
        end
        
        function positionTimerFcn(obj,varargin)            
            try
                if ~obj.hAsyncSerialQueue.isCallbackPending
                    obj.getPositionAsync(@setPosition);
                end
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
            
            function setPosition(position)
                obj.lastKnownPosition = position;
            end
        end
        
        function getPositionAsync(obj,callback)
            req = uint8('C');
            rspBytes = 1+3*4+1;
            obj.hAsyncSerialQueue.writeReadAsync(req,rspBytes,@callback_);
            
            function callback_(rsp)                
                v = typecast(rsp(2:end-1),'int32');
                v = obj.stepsToMicrons(v);
                
                callback(v);
            end
        end
        
        function tf = queryMoving(obj)
            % MPC200: there is no explicit command to query if axes are
            % active
            tf = obj.isMoving;
        end
        
        function v = queryPosition(obj)
            req = uint8('C');
            rspBytes = 1+3*4+1;
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            v = typecast(rsp(2:end-1),'int32');
            v = obj.stepsToMicrons(v);
            
            obj.lastKnownPosition = v;
        end
        
        function move(obj,position,timeout_s)
            if nargin < 3 || isempty(timeout_s)
                timeout_s = obj.defaultTimeout_s;
            end
            
            obj.moveAsync(position);
            obj.moveWaitForFinish(timeout_s);
        end
        
        function moveAsync(obj,position,callback)
            if nargin < 3 || isempty(callback)
                callback = [];
            end
            
            % Setting a position less than 0 can result in inf move
            % sequence
            if any(position<0)
                return;
            end
            
            assert(~obj.isMoving,'MPC200: Move is already in progress');
            
            if any(isnan(position))
                % fill in commands for position
               pos = obj.queryPosition();
               position(isnan(position)) = pos(isnan(position));
            end
            
            obj.isMoving = true;
            
            steps = obj.micronsToSteps(position);
            
            steps = typecast(int32(steps),'uint8');
            cmd = [uint8('M'), steps(:)'];
            
            rspBytes = 1;
            try
                obj.hAsyncSerialQueue.writeReadAsync(cmd,rspBytes,@callback_);
            catch ME
                obj.isMoving = false;
                rethrow(ME);
            end
            
            function callback_(rsp)
                obj.isMoving = false;
                
                if ~isempty(callback)
                    callback();
                end
            end
        end
        
        function moveWaitForFinish(obj,timeout_s)
            if nargin < 2 || isempty(timeout_s)
                timeout_s = obj.defaultTimeout_s;
            end
            
            s = tic();
            while toc(s) <= timeout_s
                if obj.isMoving
                    pause(0.05); % still moving
                else
                    obj.queryPosition();
                    return;
                end
            end
            
            % if we reach this, the move timed out
            obj.stop();
            obj.queryPosition();
            error('Motor %s: Move timed out.\n',obj.name);
        end
        
        function stop(obj)
            if most.idioms.isValidObj(obj.hAsyncSerialQueue) && obj.isMoving
                req = uint8(3); % ^C
                rspBytes = 1;
                rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
                assert(rsp==uint8(13));
                obj.isMoving = false;
            end
        end
        
        function startHoming(obj)
            req = uint8('H');
            rspBytes = 1;
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            assert(rsp==uint8(13));
        end
    end
    
    %% Internal methods
    methods (Hidden)
        function errorFcn(obj,varargin)
            stop(obj.hPositionTimer);
            obj.errorMsg = sprintf('MPC200: Serial communication error\n');
            fprintf(2,'%s',obj.errorMsg);
        end
    end
    
    methods (Access = private)
        function steps = micronsToSteps(obj,um)
            steps = um * 16;
            steps(steps>400e3)  =  400e3;
            steps(steps<-400e3) = -400e3;
            steps = int32(steps);
        end
        
        function um = stepsToMicrons(obj,steps)
            um = double(steps)/16;
        end
        
        % throws
        function val = infoHardware(obj)            
            MAX_NUM_DRIVES = 4;
            rspBytes = 1+MAX_NUM_DRIVES+1;
            rsp = obj.hAsyncSerialQueue.writeRead(uint8('U'),rspBytes);
            numDrives   = rsp(1);
            driveStatus = rsp(2:5);
            
            rspBytes = 4;
            rsp = obj.hAsyncSerialQueue.writeRead(uint8('K'),rspBytes);
            activeDrive  = rsp(1);
            majorVersion = rsp(2);
            minorVersion = rsp(3);
            
            val = sprintf('Firmware version %d.%d - Drive %d of %d active',majorVersion,minorVersion,activeDrive,numDrives);
        end
        
        function setRoeMode(obj, val)
            assert(isnumeric(val) && any(ismember(0:1:9, val)), 'Invalid Mode! Roe Modes range from 0-9');
            req = [uint8('L') uint8(val)];
            rspBytes = 1;
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            assert(rsp==uint8(13));
        end
        
        function calibrate(obj)
            req = uint8('N');
            rspBytes = 1;
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes, 8);
            assert(rsp==uint8(13));
        end
    end
end

function s = defaultMdfSection()
    s = [...
            makeEntry('comPort',1,'Integer identifying COM port for controller')...
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
% MPC200_Async.m                                                           %
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
