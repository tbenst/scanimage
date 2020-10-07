classdef MP285_Async < dabs.interfaces.MotorController & most.HasMachineDataFile
    %dabs.interfaces.MotorController
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
        mdfHeading = 'MP285';
        
        %Value-Optional properties
        mdfDependsOnClasses; %#ok<MCCPI>
        mdfDirectProp; %#ok<MCCPI>
        mdfPropPrefix; %#ok<MCCPI>
        
        mdfDefault = defaultMdfSection();
    end
    
    properties (Constant)
        availableBaudRates = [1200 2400 4800 9600 19200];
        defaultBaudRate = 9600;
    end
    
    %% CLASS-SPECIFIC PROPERTIES
    properties (Constant,Hidden)        
        postResetDelay = 0.2; %Time, in seconds, to wait following a reset command before proceeding
        initialVelocity = 1300; %Start at max velocity in fine resolution mode       
        maxVelocityFine = 1300; %Max velocity in fine resolution mode
        resolutionBestRaw = 1e-6;
    end
       
    % TODO: These props may be dup-ing hardware state.
    properties (SetAccess=private,Hidden)
        fineVelocity; % cached velocity for resolutionMode = 'fine'
        coarseVelocity; % cached velocity for resolutionMode = 'coarse'        
    end
    
    properties (Hidden,SetAccess=protected)
        resolutionModeMap = getResolutionModeMap();
    end
    
    properties
        resolutionMode;
    end

    properties (Dependent)
        manualMoveMode; %Specifies if 'continuous' or 'pulse' mode is currently configured for manual moves, e.g. joystick or ROE
        inputDeviceResolutionMode; %Specifies if 'fine' or 'coarse' resolutionMode is being used for manual moves, e.g. with joystick or ROE
        displayMode; %Specifies if 'absolute' or 'relative' coordinates, with respect to linear controller itself, are currently being displayed        
        velocityRaw;
        resolutionRaw;
        maxVelocityRaw;
    end
   
    %% CONSTRUCTOR/DESTRUCTOR
    methods

        function obj = MP285_Async(name)
            obj = obj@dabs.interfaces.MotorController(name);
            
            custMdfHeading = sprintf('MP285 (%s)',name);
            obj = obj@most.HasMachineDataFile(true, custMdfHeading);
            
            comPort_ = obj.mdfData.comPort;
            validateattributes(comPort_,{'numeric'},{'scalar','integer','positive'});
            obj.comPort = comPort_;
            
            try
                obj.reinit();
            catch ME
                most.ErrorHandler.logAndReportError(ME,['MP285 failed to initialize. Error: ' ME.message]);
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
                wasInitialized = ~isempty(obj.hAsyncSerialQueue);
                if wasInitialized
                    obj.resetHook();
                end
                
                if most.idioms.isValidObj(obj.hPositionTimer)
                    stop(obj.hPositionTimer);
                end
                most.idioms.safeDeleteObj(obj.hPositionTimer);
                most.idioms.safeDeleteObj(obj.hAsyncSerialQueue);
                obj.hAsyncSerialQueue = [];
                
                if wasInitialized
                    pause(0.5); % after closing com port, wait befor reopening, otherwise it can fail
                end
                
                comport_str = sprintf('COM%d', obj.comPort);
                obj.hAsyncSerialQueue = dabs.generic.AsyncSerialQueue(comport_str,'BaudRate',obj.defaultBaudRate);
                obj.hAsyncSerialQueue.ErrorFcn = @obj.errorFcn;
                
                obj.hPositionTimer = timer('Name','MP285 position query timer',...
                    'ExecutionMode','fixedRate',...
                    'Period',1,...
                    'TimerFcn',@obj.positionTimerFcn);
                
                obj.stop();
                start(obj.hPositionTimer);
                
                obj.errorMsg = '';
                info = obj.infoHardware();
                fprintf('MP285 Stage controller initialized: %s\n',info);
                
                % Sets the device velocity for each resolution mode so that it
                % will update appropriately when you change resolution mode.
                % Otherwise this will not change.
                resolutionModes = obj.resolutionModeMap.keys;
                for i = 1:numel(resolutionModes)
                    resMode = resolutionModes{i};
                    resModeVelocity = obj.initialVelocity * obj.resolutionModeMap(resMode);
                    obj.([resMode 'Velocity']) = resModeVelocity;
                    obj.resolutionMode = resMode;
                end
                
                obj.resolutionMode = 'coarse';
            catch ME
                obj.errorMsg = ME.message;
                rethrow(ME);
            end
        end
        
        function positionTimerFcn(obj, varargin)
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
        
        function getPositionAsync(obj, callback)
            req = [uint8('c') uint8(13)];
            obj.hAsyncSerialQueue.writeReadAsync(req,13,@callback_);
            
            function callback_(rsp)                
                v = typecast(rsp(1:end-1),'int32');
                v = double(v);
                v = v(:)'.*4e-2;
                
                callback(v);
            end
        end
        
        function tf = queryMoving(obj)
            % MP285: No Explicit command to query if axes are active.
            % Previous implementation was just chcking whether an
            % asyncReply was pending...
            tf = obj.isMoving;
        end
        
        function v = queryPosition(obj)
            req = [uint8('c') uint8(13)];
            rsp = obj.hAsyncSerialQueue.writeRead(req,13);
            v = typecast(rsp(1:end-1),'int32');
            v = double(v);
            v = v(:)'.*4e-2;
            
            obj.lastKnownPosition = v;
        end
        
        function move(obj, position, timeout_s)
            if nargin < 3 || isempty(timeout_s)
                timeout_s = obj.defaultTimeout_s;
            end
            
            obj.moveAsync(position);
            obj.moveWaitForFinish(timeout_s);
        end
        
        function moveAsync(obj, position, callback)
            if nargin < 3 || isempty(callback)
                callback = [];
            end
            
            assert(~obj.isMoving,'MP285: Move is already in progress');
            
            if any(isnan(position))
                % fill in commands for position
               pos = obj.queryPosition();
               position(isnan(position)) = pos(isnan(position));
            end
            
            obj.isMoving = true;
            
            steps = position./4e-2;
            cmd = [uint8('m'), typecast(int32(steps),'uint8'), uint8(13)];%steps(:)'];
            % Move command does not expect a response...?
%             rspBytes = [];
            rspBytes = 1;
            try
%                 obj.hAsyncSerialQueue.writeRead(cmd,rspBytes);
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
        
        function moveWaitForFinish(obj, timeout_s)
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
                req = [uint8(3) uint8(13)]; % ^C
                rspBytes = 1;
                rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
                assert(rsp==uint8(13));
                obj.isMoving = false;
            end
        end
        
        function startHoming(obj)
            % No Op? 
            fprintf('Homing?\n');
        end
        
    end
    
    %% PROPERTY ACCESS METHODS
    methods

        % throws
        function v = infoHardware(obj)
           v = obj.zprpGetStatusProperty('infoHardware');             
        end

        function set.velocityRaw(obj,val)
            assert(isscalar(val),'The MP-285 does not support set axis-specific velocities.');
            assert(val <= obj.maxVelocityRaw,'Velocity value provided exceeds maximum permitted value (%.2g)',obj.maxVelocityRaw);
            
            pname = [obj.resolutionMode 'Velocity'];
            obj.(pname) = val;
            obj.zprpSetVelocityAndResolutionOnDevice();
        end
        
        function v = get.velocityRaw(obj)
            pname = [obj.resolutionMode 'Velocity'];
            v = obj.(pname);
        end       
       
        function v = get.resolutionRaw(obj)            
            v = obj.resolutionBestRaw .* obj.resolutionModeMap(obj.resolutionMode);
        end
            
        function v = get.maxVelocityRaw(obj)
            v = obj.maxVelocityFine * obj.resolutionModeMap(obj.resolutionMode); 
        end        

        function set.resolutionMode(obj,val)
            assert(obj.resolutionModeMap.isKey(val)); %#ok<MCSUP>
            obj.resolutionMode = val;
            obj.zprpSetVelocityAndResolutionOnDevice();
        end
        
        function v = get.manualMoveMode(obj)
           v = obj.zprpGetStatusProperty('manualMoveMode');             
        end
        
        function v = get.inputDeviceResolutionMode(obj)
           v = obj.zprpGetStatusProperty('inputDeviceResolutionMode');             
        end
        
        function v = get.displayMode(obj)
           v = obj.zprpGetStatusProperty('displayMode');             
        end
        
    end    
    
    methods (Access=private)
        function val = zprpGetStatusProperty(obj,statusProp)
            status = obj.getStatus();
            val = status.(statusProp);
        end
        
        function zprpSetVelocityAndResolutionOnDevice(obj)
            val = obj.([obj.resolutionMode 'Velocity']);
            
            val = uint16(val);
            switch obj.resolutionMode
                case 'coarse'
                    val = bitset(val,16,0); % set bit 16 to 0
                case 'fine'
                    val = bitset(val,16,1); % set bit 16 to 1
                otherwise
                    error('Unknown resolution mode: %s',obj.resolutionMode)
            end
            
            req = [uint8('V') typecast(uint16(val), 'uint8') uint8(13) ];
            obj.hAsyncSerialQueue.writeRead(req,1);
        end

    end
        
    %% ABSTRACT METHOD IMPLEMENTATIONS
    methods (Access=protected,Hidden)
        
        function resetHook(obj)
            req = [uint8('r') uint8(13)];
            obj.hAsyncSerialQueue.writeRead(req,[]);
            pause(5);
        end
        
        % Home?
%         function zeroHardHook(obj,coords)
%             assert(all(coords),'Cannot zeroHard individual dimensions.');
%             obj.hRS232.sendCommandSimpleReply('o');
%         end
        
    end
    
    %% HIDDEN METHODS
    methods (Hidden)
        
        % throws
        function statusStruct = getStatus(obj,verbose)
            %function getStatus(obj,verbose)
            %   verbose: Indicates if status information should be displayed to command line. If omitted/empty, false is assumed
            %   statusStruct: Structure containing fields indicating various aspects of the device status...
            %           invertCoordinates: Array in format appropriate for invertCoordinates property
            %           displayMode: One of {'absolute' 'relative'} indicating which display mode controller is in
            %           inputDeviceResolutionMode: One of {'fine','coarse'} indicating resolution mode of input device, e.g. ROE or joystick.
            %           resolutionMode: One of {'fine','coarse'} indicating resolution mode of device with respect to its computer interface -- i.e. the 'resolutionMode' of this class
            %
            
            if nargin < 2 || isempty(verbose)
                verbose = false;
            end
            req = [uint8('s') uint8(13)];
            rspBytes = 33;
            v = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            v = v(1:end-1);
            status = double(v);
            
            %Parsing pertinent values based on status return data table in MP-285 manual
            statusStruct.invertCoordinates = [status(2) status(3) status(4)] - [0 2 4];
            statusStruct.infoHardware = word2str(status(31:32));
            
            flags = dec2bin(uint8(status(1)),8);
            flags2 = dec2bin(uint8(status(16)),8);
            
            if str2double(flags(2))
                statusStruct.manualMoveMode = 'continuous';
            else
                statusStruct.manualMoveMode = 'pulse';
            end
            
            if str2double(flags(3))
                statusStruct.displayMode = 'relative'; %NOTE: This is reversed in the documentation (rev 3.13)
            else
                statusStruct.displayMode = 'absolute'; %NOTE: This is reversed in the documentation (rev 3.13)
            end
            
            if str2double(flags2(6))
                statusStruct.inputDeviceResolutionMode = 'fine';
            else
                statusStruct.inputDeviceResolutionMode = 'coarse';
            end
            
            speedval = 2^8*status(30) + status(29);
            if speedval >= 2^15
                statusStruct.resolutionMode = 'fine';
                speedval = speedval - 2^15;
            else
                statusStruct.resolutionMode = 'coarse';
            end
            statusStruct.resolutionModeVelocity = speedval;
            
            if verbose
                disp(['FLAGS: ' num2str(dec2bin(status(1)))]);
                disp(['UDIRX: ' num2str(status(2))]);
                disp(['UDIRY: ' num2str(status(3))]);
                disp(['UDIRZ: ' num2str(status(4))]);
                
                disp(['ROE_VARI: ' word2str(status(5:6))]);
                disp(['UOFFSET: ' word2str(status(7:8))]);
                disp(['URANGE: ' word2str(status(9:10))]);
                disp(['PULSE: ' word2str(status(11:12))]);
                disp(['USPEED: ' word2str(status(13:14))]);
                
                disp(['INDEVICE: ' num2str(status(15))]);
                disp(['FLAGS_2: ' num2str(dec2bin(status(16)))]);
                
                disp(['JUMPSPD: ' word2str(status(17:18))]);
                disp(['HIGHSPD: ' word2str(status(19:20))]);
                disp(['DEAD: ' word2str(status(21:22))]);
                disp(['WATCH_DOG: ' word2str(status(23:24))]);
                disp(['STEP_DIV: ' word2str(status(25:26))]);
                disp(['STEP_MUL: ' word2str(status(27:28))]);
                
                %I'm not sure what happens to byte #28
                
                %Handle the Remote Speed value. Unlike all the rest...it's big-endian.
                speedval = 2^8*status(30) + status(29);
                if strcmpi(statusStruct.resolutionMode,'coarse')
                    disp('XSPEED RES: COARSE');
                else
                    disp('XSPEED RES: FINE');
                end
                disp(['XSPEED: ' num2str(speedval)]);
                
                disp(['VERSION: ' word2str(status(31:32))]);
            end            
            
            function outstr = word2str(bytePair)
                val = 2^8*bytePair(2) + bytePair(1); %value comes in little-endian
                outstr = num2str(val);
            end
        end
    end
    
end

function resolutionModeMap = getResolutionModeMap()
    %Implements a static property containing Map of resolution multipliers to apply for each of the named resolutionModes
    resolutionModeMap = containers.Map();
    resolutionModeMap('fine') = 1;
    resolutionModeMap('coarse') = 5;
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
% MP285_Async.m                                                            %
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
