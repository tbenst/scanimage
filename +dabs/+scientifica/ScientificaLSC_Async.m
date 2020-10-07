classdef ScientificaLSC_Async < dabs.interfaces.MotorController & most.HasMachineDataFile
    %%% Abstract property realizations (dabs.interfaces.MotorController)
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
        mdfHeading = 'Scientifica LSC';
        
        %Value-Optional properties
        mdfDependsOnClasses; %#ok<MCCPI>
        mdfDirectProp; %#ok<MCCPI>
        mdfPropPrefix; %#ok<MCCPI>
        
        mdfDefault = defaultMdfSection();
    end
    
    %% CLASS-SPECIFIC PROPERTIES    
    properties (SetAccess=protected,Dependent)
        infoHardware;
    end
    
    properties (Constant)
        availableBaudRates = 9600;
        defaultBaudRate = 9600;
    end
    
    properties (SetAccess=protected)
        stageType; %Specifies type of stage assembly connected to stage controller, e.g. 'patchstar' or 'mmtp'. Names match that specified in LinLab software.
        initialized = false;
    end
    
    properties (Dependent)               
        current; %2 element array - [stationaryCurrent movingCurrent], specified as values 1-255. Not typically adjusted from default.
        velocityStart; %Scalar or 3 element array indicating/specifying start velocity to use during moves.
    end
    
    properties (Dependent,Hidden)
        positionUnitsScaleFactor; %These are the UUX/Y/Z properties. %TODO: Determine if there is any reason these should be user-settable to be anything other than their default values (save for inverting). At moment, none can be determined. Perhaps related to steps.
        limitReached;
    end
        
    properties (Hidden)
        defaultCurrent; %Varies based on stage type
        defaultPositionUnitsScaleFactor; %Varies based on stage type. This effectively specifies the resolution of that stage type.
    end   
    
    properties (Hidden, Constant)
        defaultVelocityStart = 5000; %Default value for /all/ stage types
        defaultAcceleration = 500; %Default value for /all/ stage types       
    end
    
    properties (SetAccess=protected,Dependent,Hidden)
        velocityRaw;
        accelerationRaw;
    end
    
    properties(Hidden, SetAccess = protected)
        axisMap = {'X', 'Y', 'Z'};
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
%     properties (SetAccess=protected,Dependent,Hidden)
%         positionAbsoluteRaw;
%         velocityRaw;
%         accelerationRaw;
%         invertCoordinatesRaw;
%         resolutionRaw;
%     end
%     
    properties (SetAccess=protected,Hidden)
        maxVelocityRaw;
    end
%     
%     properties (SetAccess=protected,Hidden)
%         positionDeviceUnits = 1e-7;
%         velocityDeviceUnits = nan;
%         accelerationDeviceUnits = nan;
%     end
    
    properties
        twoStepDistanceThreshold = 100; % Distance threshold, in positionUnits, below which moves with twoStepEnable=true will be done in only one step (using the 'slow' step). Moves above that threshold will will be done in two steps. (This is only applicable when twoStepMoveEnable is true.)
        
        twoStepEnable = false;
        twoStepTargetPosn;
        twoStepMoveState = 'none'; %?
        twoStepPropCache;
        
        twoStepSlowProps = struct();
        twoStepFastProps = struct();
        
        twoStepPropNames = {'moveMode' 'resolutionMode' 'velocity'}; %Note this order matters -- it's the order in which the properties will be get/set on cache/restore
    end

    %% CONSTRUCTOR/DESTRUCTOR
    methods
        
        function obj = ScientificaLSC_Async(name)
            obj = obj@dabs.interfaces.MotorController(name);
            
            custMdfHeading = sprintf('Scientifica LSC (%s)',name);
            obj = obj@most.HasMachineDataFile(true, custMdfHeading);
            
            comPort_ = obj.mdfData.comPort;
            validateattributes(comPort_,{'numeric'},{'scalar','integer','positive'});
            obj.comPort = comPort_;
            
            % Validate Stage type ? 
            obj.stageType = obj.mdfData.stageType;
            
            %%%
            try
                obj.reinit();
            catch ME
                most.ErrorHandler.logAndReportError(ME,['Scientifica stage interface failed to initialize. Error: ' ME.message]);
            end
        end
        
        function delete(obj)
            try
                obj.stop();
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
            if most.idioms.isValidObj(obj.hPositionTimer)
                stop(obj.hPositionTimer);
            end
            most.idioms.safeDeleteObj(obj.hPositionTimer);
            most.idioms.safeDeleteObj(obj.hAsyncSerialQueue);
        end

    end
    
    methods (Hidden)
        function ziniInitializeDefaultValues(obj)            
            stageTypeMap = obj.stageTypeMap();
            assert(ischar(obj.stageType) && stageTypeMap.isKey(obj.stageType),'Unrecognized stageType supplied (%s)',obj.stageType);
            stageInfo = stageTypeMap(obj.stageType);
            
            % set stage-dependent props
            obj.maxVelocityRaw = stageInfo.maxVelocityStore;
            obj.defaultCurrent = stageInfo.defaultCurrent;
            obj.defaultPositionUnitsScaleFactor = stageInfo.defaultPositionUnitsScaleFactor;
            
            % Initialize properties
            obj.velocityRaw = obj.maxVelocityRaw;
            obj.accelerationRaw = obj.defaultAcceleration;
            obj.current = obj.defaultCurrent;
            obj.velocityStart = obj.defaultVelocityStart;
            obj.positionUnitsScaleFactor = obj.defaultPositionUnitsScaleFactor;            
            
        end
        
        function moveType = determineMoveType(obj, targetPosn)
            if obj.twoStepEnable
                if isempty(obj.twoStepDistanceThreshold)
                    moveType = 'twoStep';
                else
                    curPos = obj.queryPosition;
                    distance = abs(targetPosn - curPos);
                    if distance < obj.twoStepDistanceThreshold
                        moveType = 'oneStep';
                    else
                        moveType = 'twoStep';
                    end
                end
            else
                moveType = 'twoStep';
            end
        end
        
        function twoStepCB(obj, src, evt, varargin)
            curPosn = obj.queryPosition;
            if curPosn ~= obj.twoStepTargetPosn
                disp('Two Step');
                obj.velocityRaw = 0.2*obj.maxVelocityRaw;
                obj.moveAsync(obj.twoStepTargetPosn,@obj.twoStepFinish)
            else
                return;
            end
            
        end
        
        function twoStepFinish(obj, src, evt, varargin)
            obj.velocityRaw = obj.maxVelocityRaw;
        end
    end
    %%% I don't know that the # of response bytes is constant...
    %% DEVICE PROPERTY ACCESS METHODS 
    methods
        function val = get.infoHardware(obj)
            req = uint8(['DATE' uint8(13)]);
            rspBytes = 44;
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            val = deblank(native2unicode(rsp'));
        end
        
        function val = get.velocityRaw(obj)
            req = uint8(['TOP' uint8(13)]);
            rspBytes = 6; 
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            val = str2num(deblank(native2unicode(rsp')));
        end
        
        function set.velocityRaw(obj,val)
            req = uint8(['TOP ' num2str(val) uint8(13)]);
            rspBytes = 2;
            obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            
            actVal = obj.velocityRaw;
            if val ~= actVal
                most.idioms.dispError('WARNING: Actual value differs from set value\n');
            end
        end
        
        function val = get.accelerationRaw(obj)
            req = uint8(['ACC' uint8(13)]);
            rspBytes = 4; 
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            val = str2num(deblank(native2unicode(rsp')));
        end
        
        function set.accelerationRaw(obj,val)
            req = uint8(['ACC ' num2str(val) uint8(13)]);
            rspBytes = 2;
            obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            
            actVal = obj.accelerationRaw;
            if actVal ~= val
                most.idioms.dispError('WARNING: Actual value differs from set value\n');
            end
        end
        
        function val = get.current(obj)
            req = uint8(['CURRENT' uint8(13)]);
            rspBytes = 8;
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            val = str2num(deblank(native2unicode(rsp')));
        end
        
        function set.current(obj,val)
            req = uint8(['CURRENT ' num2str(val) uint8(13)]);
            rspBytes = 2;
            obj.hAsyncSerialQueue.writeRead(req,rspBytes);
        end

        function val = get.velocityStart(obj)
            req = uint8(['FIRST' uint8(13)]);
            rspBytes = 5; 
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            val = str2num(deblank(native2unicode(rsp')));
        end
        
        function set.velocityStart(obj,val)
            req = uint8(['FIRST ' num2str(val) uint8(13)]);
            rspBytes = 2;
            obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            
            actVal = obj.velocityStart;
            if actVal ~= val
                most.idioms.dispError('WARNING: Actual value differs from set value\n');
            end
        end

        function val = get.positionUnitsScaleFactor(obj)
            val = zeros(1,obj.numAxes); 
            for i = 1:obj.numAxes 
                req = uint8([sprintf('UU%s', obj.axisMap{i}) uint8(13)]);
                rspBytes = 6;
                rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
                val(i) = str2double(native2unicode(rsp'));
            end
        end
        
        % throws (hware). If this happens, the state of the UU (User Units)
        % vars is indeterminate.
        function set.positionUnitsScaleFactor(obj,val)
            assert(isnumeric(val) && (isscalar(val) || numel(val)==obj.numAxes)); 
            if isscalar(val)
                val = repmat(val,1,obj.numAxes);
            end
            for i = 1:obj.numAxes
                req = uint8([sprintf('UU%s %s', obj.axisMap{i}, num2str(val(i))) uint8(13)]);
                rspBytes = 2;
                obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            end
        end
        
        function val = get.limitReached(obj)
            %TODO(5AM): Improve decoding of 6 bit (2 byte) data 
            req = uint8(['LIMITS' uint8(13)]);
            rspBytes = 2;
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            resp = uint8(hex2dec(deblank(native2unicode(rsp'))));
            val = zeros(1,obj.numAxes);
            for i = 1:obj.numAxes
                val(i) = (bitget(resp,2*i-1) || bitget(resp,2*i));
            end
        end
        
    end   
    
    %% ABSTRACT METHOD IMPLEMENTATIONS
    methods
        %% New Methods
        function reinit(obj)
            try
                if obj.initialized
                    obj.resetHook();
                end
                
                if most.idioms.isValidObj(obj.hPositionTimer)
                    stop(obj.hPositionTimer);
                end
                most.idioms.safeDeleteObj(obj.hPositionTimer);
                most.idioms.safeDeleteObj(obj.hAsyncSerialQueue);
                obj.hAsyncSerialQueue = [];
                
                if obj.initialized
                    pause(0.5); % after closing com port, wait befor reopening, otherwise it can fail
                    obj.initialized = false;
                end
                
                comport_str = sprintf('COM%d', obj.comPort);
                obj.hAsyncSerialQueue = dabs.generic.AsyncSerialQueue(comport_str,'BaudRate',obj.defaultBaudRate);
                obj.hAsyncSerialQueue.ErrorFcn = @obj.errorFcn;
                
                obj.hPositionTimer = timer('Name','Scientifica LSC position query timer',...
                    'ExecutionMode','fixedRate',...
                    'Period',0.3,...
                    'TimerFcn',@obj.positionTimerFcn);
                
                obj.stop();
                %             start(obj.hPositionTimer);
                
                obj.errorMsg = '';
                
                obj.ziniInitializeDefaultValues();
                obj.initialized = true;
                start(obj.hPositionTimer);
                fprintf('Scientifica LSC Initialized!\n');
            catch ME
                obj.errorMsg = ME.message;
                ME.rethrow();
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
            req = uint8(['POS' uint8(13)]);% uint8(13)];
            rspBytes = char(13);
            obj.hAsyncSerialQueue.writeReadAsync(req,rspBytes,@callback_);
            
            function callback_(rsp) 
                v = str2num(deblank(native2unicode((rsp)))).*0.1;
                callback(v);
            end
        end
        
        function tf = queryMoving(obj)
            req = uint8(['S' uint8(13)]);
            rspBytes = 2;
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            tf = str2num(deblank(native2unicode(rsp')));
            obj.isMoving = tf;
        end
        
        function v = queryPosition(obj)
            req = uint8(['POS' uint8(13)]);
            rspBytes = char(13);
            rsp = obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            v = str2num(deblank(native2unicode(rsp))).*0.1;
            
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
            
            assert(~obj.isMoving,'Scientifica LSC: Move is already in progress');
            
            if any(isnan(position))
                % fill in commands for position
               pos = obj.queryPosition();
               position(isnan(position)) = pos(isnan(position));
            end
            
            moveType = obj.determineMoveType(position);
            
            switch moveType
                case 'twoStep'
                    obj.velocityRaw = obj.maxVelocityRaw;
                    obj.twoStepTargetPosn = position;
                    if isempty(callback)
                        callback = @obj.twoStepCB;
                    end
%                     obj.moveAsync(position, @obj.twoStepCB)
                otherwise
            end
            
            obj.isMoving = true;
            
            pos = num2str(round(position./0.1));
            cmd = uint8(['ABS ' pos(:)' uint8(13)]);
            
            rspBytes = 2;
            try
                obj.hAsyncSerialQueue.writeReadAsync(cmd,rspBytes,@callback_);
            catch ME
                obj.isMoving = false;
                rethrow(ME);
            end
            
            % isMoving query returns 0 all the time but not sure if that is
            % just because this was done with no stages connected. 
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
            if most.idioms.isValidObj(obj.hAsyncSerialQueue)
                req = uint8(['STOP' uint8(13)]);
                rspBytes = 2;
                obj.hAsyncSerialQueue.writeRead(req,rspBytes);
            end
        end
        
        function startHoming(obj)
            % No Op
        end
    
        
        %% Old Methods
        function resetHook(obj)
            %Warn user about reset() operation, if needed
            resp = questdlg('Executing reset() operation will reset the stage controller''s absolute origin and restore default values for speed and current. Proceed?','WARNING!','Yes','No','No');
            if strcmpi(resp,'No')
                return;
            end
            drawnow(); %Address questdlg() bug (service request 1-F1PZKQ)
            
            %obj.hRS232.sendCommandReceiveStringReply('RESET');

            %Restore default values of this class (and specifically for
            %stage type specified on construction)
            obj.ziniInitializeDefaultValues();           
        end  
        
        % Homing?
%         function zeroHardHook(obj,coords)
%             if ~all(coords)
%                 error('Scientifica:LinearStageController:zeroHardHook',...
%                     'It is not possible to perform zeroHard() operation on individual dimensions for device of class %s',class(obj));
%             end
%             obj.hRS232.sendCommandSimpleReply('ZERO');
%         end        
    end
    
    %% STATIC METHODS
    methods (Static)
        
        % keys: stageTypes. vals: stage info/props
        function m = stageTypeMap()
            
            m = containers.Map();
            
            m('ums') = struct( ...
                'maxVelocityStore', 40000, ... % maxVelocity, in units of positionDeviceUnits
                'defaultCurrent', [200 100], ... 
                'defaultPositionUnitsScaleFactor', -5.12);
            
            m('ums_2') = struct( ...
                'maxVelocityStore', 40000, ...
                'defaultCurrent', [250 125], ...
                'defaultPositionUnitsScaleFactor', [-4.032 -4.032 -5.12]);
            
            m('mmtp') = struct( ...
                'maxVelocityStore', 40000, ...
                'defaultCurrent', [200 100], ...
                'defaultPositionUnitsScaleFactor', -5.12);
            
            m('slicemaster') = struct( ...
                'maxVelocityStore', 40000, ...
                'defaultCurrent', [200 100], ...
                'defaultPositionUnitsScaleFactor', -5.12);
            
            m('patchstar') = struct( ...
                'maxVelocityStore', 30000, ...
                'defaultCurrent', [230 125], ...
                'defaultPositionUnitsScaleFactor', -6.4);
            
            m('patchstar_2') = struct( ...
                'maxVelocityStore', 30000, ...
                'defaultCurrent', [250 125], ...
                'defaultPositionUnitsScaleFactor', -6.4);
            
            m('mmsp') = struct( ...
                'maxVelocityStore', 30000, ...
                'defaultCurrent', [175 125], ...
                'defaultPositionUnitsScaleFactor', -5.12);
            
            m('mmsp_z') = struct( ...
                'maxVelocityStore', 30000, ...
                'defaultCurrent', [175 125], ...
                'defaultPositionUnitsScaleFactor', -5.12);
            
            m('mmbp') = struct( ...
                'maxVelocityStore', 20000, ...
                'defaultCurrent', [200 125], ...
                'defaultPositionUnitsScaleFactor', [-4.032 -4.032 -6.4]);
            
            m('imtp') = struct( ...
                'maxVelocityStore', 40000, ...
                'defaultCurrent', [175 125], ...
                'defaultPositionUnitsScaleFactor', -5.12);
            
            m('slice_scope') = struct( ...
                'maxVelocityStore', 20000, ...
                'defaultCurrent', [200 125], ...
                'defaultPositionUnitsScaleFactor', [-4.032 -4.032 -6.4]);
            
            m('condenser') = struct( ...
                'maxVelocityStore', 20000, ...
                'defaultCurrent', [200 125], ...
                'defaultPositionUnitsScaleFactor', [-4.032 -4.032 -6.4]);
            
            m('ivm_manipulator') = struct( ...
                'maxVelocityStore', 30000, ...
                'defaultCurrent', [255 125], ...
                'defaultPositionUnitsScaleFactor', -5.12);
        end
        
    end
end

function s = defaultMdfSection()
    s = [...
            makeEntry('comPort',1,'Integer identifying COM port for controller')...
            makeEntry('stageType','slice_scope','String identifying stage type i.e. ''mmtp'', ''slice_scope'', etc ')...
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
% ScientificaLSC_Async.m                                                   %
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
