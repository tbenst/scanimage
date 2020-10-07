classdef Motors < scanimage.interfaces.Component & most.HasMachineDataFile & most.HasClassDataFile 
    %%% ABSTRACT PROPERTY REALIZATION (most.Model)
    properties (Hidden, SetAccess=protected)
        mdlPropAttributes = initPropAttributes();
        mdlHeaderExcludeProps = {'hMotors'};
    end
    
    %%% ABSTRACT PROPERTY REALIZATIONS (most.HasMachineDataFile)
    properties (Constant, Hidden)
        %Value-Required properties
        mdfClassName = mfilename('class');
        mdfHeading = 'Motors';
        
        %Value-Optional properties
        mdfDependsOnClasses; %#ok<MCCPI>
        mdfDirectProp;       %#ok<MCCPI>
        mdfPropPrefix;       %#ok<MCCPI>
        
        mdfDefault = defaultMdfSection();
    end
    
    %%% ABSTRACT PROPERTY REALIZATION (scanimage.interfaces.Component)
    properties (SetAccess = protected, Hidden)
        numInstances = 0;
    end
    
    properties (Constant, Hidden)
        COMPONENT_NAME = 'Motors';               % [char array] short name describing functionality of component e.g. 'Beams' or 'FastZ'
        PROP_TRUE_LIVE_UPDATE = {};              % Cell array of strings specifying properties that can be set while the component is active
        PROP_FOCUS_TRUE_LIVE_UPDATE = {};        % Cell array of strings specifying properties that can be set while focusing
        DENY_PROP_LIVE_UPDATE = {};              % Cell array of strings specifying properties for which a live update is denied (during acqState = Focus)
        
        FUNC_TRUE_LIVE_EXECUTION = {}; % Cell array of strings specifying functions that can be executed while the component is active
        FUNC_FOCUS_TRUE_LIVE_EXECUTION = {};         % Cell array of strings specifying functions that can be executed while focusing
        DENY_FUNC_LIVE_EXECUTION = {'saveUserDefinedPositions' 'loadUserDefinedPositions'};    % Cell array of strings specifying functions for which a live execution is denied (during acqState = Focus)
    end
    
    %% USER PROPS
    properties (SetObservable)
        moveTimeout_s = 10;
        axesPosition = [];
        backlashCompensation = [0 0 0];
        userDefinedPositions = repmat(struct('name','','coords',[]),0,1); % struct containing positions defined by users
        minPositionQueryInterval_s = 1e-3;
    end
    
    properties (Dependent,SetObservable,Transient)
        motorPosition;
        samplePosition;
        moveInProgress;
        isRelativeZeroSet;
        errorMsg;
        errorTf;
        isAligned;
    end        
        
    properties (Dependent,SetObservable)
        azimuth
        elevation
    end
    
    properties (SetObservable, SetAccess = private, Transient)
        markers = scanimage.components.motors.MotorMarker.empty(1,0);
        simulatedAxes = [false false false];
    end
    
    %% Internal properties
    properties (SetAccess = private,Hidden)
        hMotors = {};
        legacyMotors = false(1,0);
        motorDimMap = {};
        
        hCSCoordinateSystem;
        hCSRotation;
        hCSAlignment;
        hCSAxesScaling;
        hCSAxesPosition;
        hCSStageAbsolute
        hCSSampleAbsolute
        hCSStageRelative
        hCSSampleRelative
        hCSInversion
        hCSAntiInversion
        
        hListeners = event.listener.empty(1,0);
        hMotorListeners = event.listener.empty(1,0);
        
        classDataFileName
        lastPositionQuery = tic();
    end
    
    properties (Access = private)
        hCSAntiRotation
        hCSAxesAntiScaling
    end
    
    properties (Hidden,SetObservable,SetAccess = private)
        calibrationPoints = cell(0,2);
    end
    
    properties (Hidden)
        hErrorCallBack;
        mdfHasChanged;
    end
    
    %% Lifecycle
    methods
        function obj = Motors(hSI)
            obj = obj@scanimage.interfaces.Component(hSI);
            
            % Determine CDF name and path
            if isempty(obj.hSI.classDataDir)
                pth = most.util.className(class(obj),'classPrivatePath');
            else
                pth = obj.hSI.classDataDir;
            end
            classNameShort = most.util.className(class(obj),'classNameShort');
            obj.classDataFileName = fullfile(pth, [classNameShort '_classData.mat']);
            
            obj.ensureClassDataFileProps();
            
            try
                obj.validateMdf();
                obj.initCoordinateSystems();
                obj.initMotors();
            catch ME
                obj.delete();
                rethrow(ME);
            end
            
            obj.numInstances = numel(obj.hMotors);
            
            obj.loadClassData();
            
            obj.setPositionTargetToCurrentPosition();
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hListeners);
            most.idioms.safeDeleteObj(obj.hMotorListeners);
            for idx = 1:numel(obj.hMotors)
                most.idioms.safeDeleteObj(obj.hMotors{idx});
            end
            
            obj.saveClassData();
        end
    end
    
    methods (Access = private)
        function initCoordinateSystems(obj)
           % initialize coordinate systems
            obj.hCSCoordinateSystem  = scanimage.mroi.coordinates.CSLinear('Motor Root Coordinates',  3, obj.hSI.hCoordinateSystems.hCSReference);
            
            obj.hCSAlignment         = scanimage.mroi.coordinates.CSLinear('Motor Alignment',        3, obj.hCSCoordinateSystem);
            
            obj.hCSInversion         = scanimage.mroi.coordinates.CSLinear('Stage Inversion',        3, obj.hCSAlignment); 
            obj.hCSInversion.lock    = true; % do not load from class data file, since it is set by MDF
            
            obj.hCSRotation          = scanimage.mroi.coordinates.CSLinear('Motor Rotation',         3, obj.hCSInversion);
            obj.hCSRotation.lock     = true;
            obj.hCSAxesScaling       = scanimage.mroi.coordinates.CSLinear('Motor Scaling',          3, obj.hCSRotation);
            obj.hCSAxesScaling.lock  = true;
            obj.hCSAxesPosition      = scanimage.mroi.coordinates.CSLinear('Motor Axes Coordinates', 3, obj.hCSAxesScaling);
            obj.hCSAxesPosition.fromParentAffine = eye(4);
            obj.hCSAxesPosition.lock = true;
            obj.hCSAxesAntiScaling   = scanimage.mroi.coordinates.CSLinear('Motor Anti Scaling',     3, obj.hCSAxesPosition);
            obj.hCSAxesAntiScaling.lock = true;
            obj.hCSAntiRotation      = scanimage.mroi.coordinates.CSLinear('Motor Anti Rotation',    3, obj.hCSAxesAntiScaling);
            obj.hCSAntiRotation.lock = true;
            
            obj.hCSStageAbsolute     = scanimage.mroi.coordinates.CSLinear('Stage Absolute',         3, obj.hCSAntiRotation);
            obj.hCSStageRelative     = scanimage.mroi.coordinates.CSLinear('Stage Relative',         3, obj.hCSStageAbsolute);
            
            obj.hCSAntiInversion     = scanimage.mroi.coordinates.CSLinear('Stage Anti Inversion',   3, obj.hCSStageAbsolute);
            obj.hCSAntiInversion.lock = true;
            
            obj.hCSSampleAbsolute    = scanimage.mroi.coordinates.CSLinear('Sample Absolute',        3, obj.hCSAntiInversion);
            obj.hCSSampleRelative    = scanimage.mroi.coordinates.CSLinear('Sample Relative',        3, obj.hCSSampleAbsolute);
            
            addEventListeners('changed',@obj.csUpdateAntiCS,{obj.hCSRotation,obj.hCSAlignment,obj.hCSAxesScaling,obj.hCSInversion});
            addEventListeners('changed',@obj.csChanged,{obj.hCSCoordinateSystem,...
                obj.hCSRotation,obj.hCSAxesScaling,obj.hCSInversion,obj.hCSAlignment,obj.hCSAxesPosition,...
                obj.hCSStageAbsolute,obj.hCSSampleAbsolute,obj.hCSStageRelative,obj.hCSSampleRelative});
            
            obj.updateScalingAndInversion();
            
            %%% local function
            function addEventListeners(eventName,callback,objects)
                for idx = 1:numel(objects)
                    obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(objects{idx},eventName,callback);
                end
            end
        end
    end
    
    %% Friend methods
    methods (Hidden)
        function reloadMdf(obj,varargin)
            obj.reloadMdf@scanimage.interfaces.Component(varargin{:});
            
            obj.validateMdf();
            obj.mdfHasChanged = true;
            
            obj.updateScalingAndInversion();
        end
        
        function updateScalingAndInversion(obj)
            % apply Inversion. Anti-Inversion is going to be set
            % automatically through listeners
            stageToSample = eye(4);
            stageToSample([1,6,11]) = (-1).^(~obj.mdfData.axisMovesObjective);
        
            obj.hCSInversion.fromParentAffine = stageToSample;
            
            % apply Scaling. Anti-Scaling is going to be set
            % automatically through listeners
            scaleT = eye(4);
            scaleT([1 6 11]) = obj.mdfData.scaleXYZ;
            obj.hCSAxesScaling.toParentAffine = scaleT;
        end
    end
    
    %% Init functions        
    methods (Access = private)
        function validateMdf(obj)
            if isfield(obj.mdfData,'motorControllerType') || ~isfield(obj.mdfData.motors, 'name')
                fprintf(2,'MDF settings for Motors are outdated. Exit ScanImage and run the configuration editor to migrate the settings.\n');
                obj.mdfData = makeEmptyMdf();
            end
            
            % validate scaleXYZ
            assert(isnumeric(obj.mdfData.scaleXYZ) && isequal(size(obj.mdfData.scaleXYZ),[1,3]) && ...
                  all(isreal(obj.mdfData.scaleXYZ)) && all(obj.mdfData.scaleXYZ~=0) && all(~isnan(obj.mdfData.scaleXYZ)) && all(~isinf(obj.mdfData.scaleXYZ)), ...
                  'Motors MDF: Incorrect entry for scaleXYZ. Must be a [1x3] numeric array.');
            
            assert(islogical(obj.mdfData.axisMovesObjective) && isequal(size(obj.mdfData.axisMovesObjective),[1,3]), ...
                  'Motors MDF: Incorrect entry for axisMovesObjective. Must be a [1x3] logical array.');
            
            % validate motorEntries
            assert(isstruct(obj.mdfData.motors),'Motors MDF: motors must be a struct array');
            fieldNames = fieldnames(obj.mdfData.motors);
            assert(ismember('name',fieldNames) && ismember('controllerType',fieldNames) && ismember('dimensions',fieldNames),...
                'Motors MDF: Incorrect format of entry ''motors''. Must be a struct array with fields ''name'' ''controller'' ''dimensions''');            
            
            % remove invalid entries from MDF
            validMask = false(1,numel(obj.mdfData.motors));
            for idx = 1:numel(obj.mdfData.motors)
                validMask(idx) = validateMdfEntry(obj.mdfData.motors(idx));
            end
            obj.mdfData.motors(~validMask) = [];            
            
            %%% local functions            
            function tfValid = validateMdfEntry(motorMdf)
                tfValid = false;
                
                if isempty(motorMdf.name) || isempty(motorMdf.controllerType)
                    return
                end
                
                if ~ischar(motorMdf.name)  || ~isvector(motorMdf.name)
                    most.idioms.warn('Invalid name for motor %s: %s',motorMdf.name);
                    return
                end
                
                if ~ischar(motorMdf.controllerType) || ~isvector(motorMdf.controllerType)
                    most.idioms.warn('Invalid controllerType for motor %s: %s',motorMdf.name,motorMdf.controller);
                    return
                end
                
                if ~ischar(motorMdf.dimensions) || ~isvector(motorMdf.dimensions) || isempty(regexpi(motorMdf.dimensions,'[XYZ-]+'))
                    most.idioms.warn('Invalid axes assignment for motor %s: %s',motorMdf.name,motorMdf.dimensions);
                    return
                end
                
                tfValid = true;
            end
            
            function mdfData = makeEmptyMdf()
                mdfData = struct();
                mdfData.scaleXYZ = [1 1 1];
                mdfData.motors = struct('name',{},'controllerType',{},'dimensions',{});
            end
        end
        
        function initMotors(obj)
            for idx = 1:numel(obj.mdfData.motors)
                motorMdf = obj.mdfData.motors(idx);
                
                registryEntry = scanimage.components.motors.MotorRegistry.searchEntry(motorMdf.controllerType);
                
                if isempty(registryEntry)
                    most.idioms.warn('Could not find motor registry entry for motor %d (%s)',idx,motorMdf.controllerType);
                    continue;
                end
                
                try
                    hMotor = registryEntry.construct(motorMdf.name);
                catch ME
                    most.ErrorHandler.logAndReportError(ME,sprintf('Initialization of Motor %s failed.',motorMdf.name));
                    continue
                end
                
                dimMap = makeMotorDimMap(hMotor,motorMdf);
                
                obj.hMotors{end+1}     = hMotor;
                obj.motorDimMap{end+1} = dimMap;
                obj.legacyMotors(end+1) = isa(hMotor,'scanimage.components.motors.legacy.LegacyMotor');
            end
            
            simulateMissingAxes();
            validateMotorDimMap();
            findSimulatedAxes();
            
            addPropertyListeners('lastKnownPosition',@obj.motorPositionChanged,obj.hMotors);
            addPropertyListeners('isMoving',@obj.motorIsMovingChanged,obj.hMotors);
            addPropertyListeners('errorMsg',@obj.errorMsgChanged,obj.hMotors);
            
            obj.queryPosition();
            
            %%% local functions            
            function map = makeMotorDimMap(hMotor,motorMdf)
                numAxes = hMotor.numAxes;
                
                if numel(motorMdf.dimensions) > numAxes
                    motorMdf.dimensions(numAxes+1:end) = [];
                    %most.idioms.warn('MDF: Motor %s had too many entries in field ''dimensions''. Truncated to ''%s''',motorMdf.name,motorMdf.dimensions);
                end
                
                map = nan(1,numAxes);
                
                Xidx = strfind(motorMdf.dimensions,'X');
                Yidx = strfind(motorMdf.dimensions,'Y');
                Zidx = strfind(motorMdf.dimensions,'Z');
                
                map(Xidx) = 1;
                map(Yidx) = 2;
                map(Zidx) = 3; 
            end
            
            function validateMotorDimMap()
                % ensure there are no double assignments of dimensions
                allDims = horzcat(obj.motorDimMap{:});
                
                Xs = sum(allDims==1);
                Ys = sum(allDims==2);
                Zs = sum(allDims==3);
                
                assert(numel(Xs)<=1,'Motors: Double assignment of X-axes.');
                assert(numel(Ys)<=1,'Motors: Double assignment of Y-axes.');
                assert(numel(Zs)<=1,'Motors: Double assignment of Z-axes.');
            end
            
            function simulateMissingAxes()
                allDims = horzcat(obj.motorDimMap{:});
                
                simX = ~any(allDims==1);
                simY = ~any(allDims==2);
                simZ = ~any(allDims==3);
                
                simMask = [simX simY simZ];
                if any(simMask)
                    registryEntry_ = scanimage.components.motors.MotorRegistry.searchEntry('simulated');
                    hMotor__ = registryEntry_.construct('SI simulated motor');
                    obj.hMotors{end+1} = hMotor__;
                    dimMap__ = 1:3;
                    dimMap__(~simMask) = NaN;
                    obj.motorDimMap{end+1} = dimMap__;
                    obj.legacyMotors(end+1) = false;
                    
                    msgSim = 'XYZ';
                    fprintf('Motors: Simulated %s axes\n',msgSim(simMask));
                end
            end
            
            function findSimulatedAxes()
                simulatedAxes__ = [false false false];
                
                registryEntry_ = scanimage.components.motors.MotorRegistry.searchEntry('simulated');
                for motorIdx = 1:numel(obj.hMotors)
                    hMotor__ = obj.hMotors{motorIdx};
                    isMotorSimulated = isa(hMotor__,registryEntry_.className);
                    map = obj.motorDimMap{motorIdx};
                    simulatedAxes__(map(~isnan(map))) = isMotorSimulated;
                end
                
                obj.simulatedAxes = simulatedAxes__;
            end
            
            function addPropertyListeners(propertyName,callback,objects)
                for idx_ = 1:numel(objects)
                    obj.hMotorListeners(end+1) = most.ErrorHandler.addCatchingListener(objects{idx_},propertyName,'PostSet',callback);
                end
            end
        end
    end
    
    %% Class data file functions
    methods (Hidden)
        function ensureClassDataFileProps(obj)
            % naming convention in class data file is to maintain backward compatibility with SI <= 2019a
            obj.ensureClassDataFile(struct('motorToRefTransform',      eye(3)), obj.classDataFileName);
            obj.ensureClassDataFile(struct('scanimageToMotorTF',       eye(4)), obj.classDataFileName);
            obj.ensureClassDataFile(struct('backlashCompensation', zeros(1,3)), obj.classDataFileName);
        end
        
        function loadClassData(obj)            
            obj.backlashCompensation = obj.getClassDataVar('backlashCompensation',obj.classDataFileName);
        end
        
        function saveClassData(obj)
            if ~obj.numInstances
                return % if motor initialization errors, don't save anything
            end
            
            try                
                obj.setClassDataVar('backlashCompensation',obj.backlashCompensation,obj.classDataFileName);
            catch ME
                most.ErrorHandler.logAndReportError(ME,'Motors: Error saving class data file.');
            end
        end
    end
    
    %% Abstract method implementation (scanimage.interfaces.Component)
    methods (Access = protected, Hidden)
        function componentStart(~)
        end
        
        function componentAbort(~)
        end
    end
    
    %% Public methdos
    methods
        function addMarker(obj,name)
            if nargin < 2 || isempty(name)
                name = inputdlg('Marker Name');
                if isempty(name) || isempty(name{1})
                    return
                end
                name = name{1};
            end
                
            obj.queryPosition();
            pos = obj.samplePosition;
            hPt = scanimage.mroi.coordinates.Points(obj.hCSSampleRelative,pos);
            hPt = hPt.transform(obj.hCSSampleAbsolute);
            
            powers = obj.hSI.hBeams.powers;            
            hMotorMarker = scanimage.components.motors.MotorMarker(name,hPt,powers);
            obj.markers(end+1) = hMotorMarker;
        end
        
        function deleteMarker(obj,id)
            if isa(id,'uint64')
                mask = [obj.markers.uuiduint64] == id;
            elseif isnumeric(id)
                mask = false(1,numel(obj.markers));
                mask(id) = true;
            elseif isa(id,'scanimage.components.motors.Marker')
                mask = obj.markers.uuidcmp(id);
            else
                mask = strcmpi(id,{obj.markers.name});
                mask = mask | strcmpi(id,{obj.markers.uuid});
            end
            
            obj.markers(mask) = [];
        end
        
        function clearMarkers(obj)
            obj.markers(:) = [];
        end
        
        function setRelativeZero(obj,dims)
            if nargin < 2
                dims = [1 2 3];
            end
            validateattributes(dims,{'numeric'},{'positive','vector','integer','<=',3,'increasing'});
            
            obj.queryPosition();
            hPt_Ref = scanimage.mroi.coordinates.Points(obj.hSI.hCoordinateSystems.hCSReference,[0 0 0]);
            
            % set stage relative zero
            hPt = hPt_Ref.transform(obj.hCSStageRelative.hParent);
            pt = hPt.points;
            
            T = obj.hCSStageRelative.toParentAffine;
            
            dimIdxs = [13 14 15];
            val = pt;
            
            dimIdxs = dimIdxs(dims);
            val = val(dims);
            
            T(dimIdxs) = val;
            obj.hCSStageRelative.toParentAffine = T;
            
            % set sample relative zero
            hPt = hPt_Ref.transform(obj.hCSSampleRelative.hParent);
            pt = hPt.points;
            
            T = obj.hCSSampleRelative.toParentAffine;
            
            dimIdxs = [13 14 15];
            val = pt;
            
            dimIdxs = dimIdxs(dims);
            val = val(dims);
            
            T(dimIdxs) = val;
            obj.hCSSampleRelative.toParentAffine = T;
        end
        
        function clearRelativeZero(obj)
            obj.hCSStageRelative.reset();
            obj.hCSSampleRelative.reset();
        end
        
        function success = reinit(obj,failedOnly)
            if nargin < 2
                failedOnly = false;
            end
            
            if obj.mdfHasChanged
                for idx = 1:numel(obj.hMotors)
                    most.idioms.safeDeleteObj(obj.hMotors{idx});
                end
                most.idioms.safeDeleteObj(obj.hMotorListeners);
                obj.hMotorListeners = event.listener.empty(1,0);
                obj.hMotors = {};
                obj.motorDimMap = {};
                obj.legacyMotors = [];
                
                obj.initMotors();
                obj.errorMsg = [];
            else
                for idx = 1:numel(obj.hMotors)
                    if ~failedOnly || ~obj.hMotors{idx}.initSuccessful
                        obj.hMotors{idx}.reinit();
                    end
                end
            end
            
            obj.queryPosition();
            success = ~obj.errorTf;
        end
    end
    
    %% Internal functions
    methods (Hidden)        
        function csChanged(obj,src,evt)
            % if any of the coordinate systems changed, trigger a dummy set
            % to update the GUI
            obj.motorPosition = NaN;
            obj.samplePosition = NaN;
            obj.axesPosition = NaN;
        end
        
        function csUpdateAntiCS(obj,src,evt)            
            % link Rotation to AntiRotation
            if ~isempty(obj.hCSRotation.toParentAffine)
                obj.hCSAntiRotation.toParentAffine = inv(obj.hCSRotation.toParentAffine);
            elseif ~isempty(obj.hCSRotation.fromParentAffine)
                obj.hCSAntiRotation.fromParentAffine = inv(obj.hCSRotation.fromParentAffine);
            else
                obj.hCSAntiRotation.reset();
            end
            
            % link Scaling to AntiScaling
            if ~isempty(obj.hCSAxesScaling.toParentAffine)
                obj.hCSAxesAntiScaling.toParentAffine = inv(obj.hCSAxesScaling.toParentAffine);
            elseif ~isempty(obj.hCSAxesScaling.fromParentAffine)
                obj.hCSAxesAntiScaling.fromParentAffine = inv(obj.hCSAxesScaling.fromParentAffine);
            else
                obj.hCSAxesAntiScaling.reset();
            end
            
            % link Inversion to AntiInversion
            if ~isempty(obj.hCSInversion.toParentAffine)
                obj.hCSAntiInversion.toParentAffine = inv(obj.hCSInversion.toParentAffine);
            elseif ~isempty(obj.hCSInversion.fromParentAffine)
                obj.hCSAntiInversion.fromParentAffine = inv(obj.hCSInversion.fromParentAffine);
            else
                obj.hCSAntiInversion.reset();
            end
            
            obj.csChanged();
            
            % update UI
            obj.azimuth = NaN;
            obj.elevation = NaN;
        end
        
        function setRotationAngles(obj,yaw,pitch,roll)
            % order of operation is important here. first yaw, then pitch, then roll
            M = makehgtform('zrotate',yaw,'yrotate',pitch,'xrotate',roll);
            
            obj.hCSRotation.fromParentAffine = M;
        end
        
        function [yaw,pitch,roll] = getRotationAngles(obj)
            M = obj.hCSRotation.fromParentAffine;
            if isempty(M)
                M = inv(obj.hCSRotation.toParentAffine);
            end
            
            % see http://planning.cs.uiuc.edu/node103.html
            yaw   = atan2(  M(2,1), M(1,1) );
            pitch = atan2( -M(3,1), sqrt(M(3,2)^2+M(3,3)^2) );
            roll  = atan2(  M(3,2), M(3,3) );
        end
        
        function motorPositionChanged(obj,src,evt)
            obj.decodeMotorPosition();
        end
        
        function motorIsMovingChanged(obj,src,evt)
            obj.moveInProgress = NaN; % trigger UI update
        end
        
        function errorMsgChanged(obj,src,evt)
            obj.errorMsg = NaN; % trigger UI update
            
            if ~isempty(obj.errorMsg) && ~isempty(obj.hErrorCallBack)
                try
                    obj.hErrorCallBack();
                catch ME
                    most.ErrorHandler.logAndReportError(ME);
                end
            end
        end
    end
    
    methods
        function setPositionTargetToCurrentPosition(obj)
            obj.queryPosition();
        end
        
        function hPt = getPosition(obj,hCS)
            if any(obj.legacyMotors)
                % legacy motors do not automatically update
                % lastKnownPosition needs to be updated here
                obj.queryPosition();
            end
            
            hPt = scanimage.mroi.coordinates.Points(obj.hSI.hCoordinateSystems.hCSReference,[0 0 0]);
            hPt = hPt.transform(hCS);
        end
        
        function hPosition = wrapPosition(obj,position)
            validateattributes(position,{'numeric'},{'nonnan','row','numel',3,'finite'});
            hPosition = scanimage.mroi.coordinates.Points(obj.hCSStageRelative,position);
        end
        
        function xyz = queryPosition(obj)
            % explicitly queries the motor positions. this method should
            % not need to be called because motors are expected to publish
            % their positions via the lastKnownPosition property
            if toc(obj.lastPositionQuery) < obj.minPositionQueryInterval_s
                return;
            end
            
            for idx = 1:numel(obj.hMotors)
                % this updates the lastKnownPosition property of the motor
                if obj.hMotors{idx}.initSuccessful
                    try
                        obj.hMotors{idx}.queryPosition();
                    catch ME
                        most.ErrorHandler.logAndReportError(ME,sprintf('Motor %s threw an error when attempting to wait for move to finish.',obj.hMotors{idx}.name));
                    end
                end
            end
            
            obj.lastPositionQuery = tic();
            
            % this reads the lastKnownPosition property of the motors and
            % transforms it into SI coordinates
            xyz = obj.decodeMotorPosition();
        end
             
        function xyz = decodeMotorPosition(obj)
            % reads the lastKnownPosition property of the motors and
            % transforms it into SI coordinates
            
            xyz = obj.hCSAxesPosition.fromParentAffine(13:15);
            
            for idx = 1:numel(obj.hMotors)
                hMotor = obj.hMotors{idx};
                
                if hMotor.initSuccessful
                    try
                        pos = hMotor.lastKnownPosition;
                        
                        motorDimMap_ = obj.motorDimMap{idx};
                        axesMask = ~isnan(motorDimMap_);
                        dimIdxs = motorDimMap_(axesMask);
                        
                        isValid = isPositionValid(pos,axesMask);
                        
                        if isValid
                            xyz(dimIdxs) = pos(axesMask);
                        else
                            most.ErrorHandler.logAndReportError('Motor %s returned an invalid position: %s',hMotor.name,mat2str(pos));
                        end
                    catch ME
                        most.ErrorHandler.logAndReportError(ME,sprintf('Motor %s threw an error when attempting to retrieve last known position.',hMotor.name));
                    end
                end
            end
            
            obj.hCSAxesPosition.fromParentAffine(13:15) = double(xyz);
            
            
            %%% Nested function
            function isValid = isPositionValid(pos,axesMask)
                isValid = true;
                
                if ~isempty(axesMask)
                    isValid = isValid & numel(pos)<=numel(axesMask); % ensure that size of pos is adequat
                    pos = pos(axesMask);
                    isValid = isValid & ~any(isnan(pos)) & ~any(isinf(pos)) & all(isreal(pos));                    
                end
            end
        end
        
        function moveMotor(obj,position)
            if any(isnan(position))
                % fill in NaNs with current motor position
                nanMask = isnan(position);
                obj.queryPosition();
                pos = obj.motorPosition;
                position(nanMask) = pos(nanMask);
            end
            
            validateattributes(position,{'numeric'},{'vector','numel',3,'nonnan','finite','real'});
            
            hPt = scanimage.mroi.coordinates.Points(obj.hCSStageRelative, position); % wrap point
            
            obj.move(hPt);
        end
        
        function moveSample(obj,position)
            if all(isnan(position))
                return
            end
            
            % fill in NaNs with current motor position
            if any(isnan(position))
                nanMask = isnan(position);
                obj.queryPosition();
                pos = obj.samplePosition;
                position(nanMask) = pos(nanMask);
            end
            
            validateattributes(position,{'numeric'},{'vector','numel',3,'nonnan','finite','real'});
            
            hPt = scanimage.mroi.coordinates.Points(obj.hCSSampleRelative, position); % wrap point
            
            obj.move(hPt);
        end
        
        function move(obj,hPt)
            % moves the motor to a point specified by scanimage.mroi.coordinates.Points
            assert(isa(hPt,'scanimage.mroi.coordinates.Points'));
            hPt = hPt.transform(obj.hCSAxesPosition);
            val = hPt.points;
            assert(~any(isnan(val)|isinf(val)),'Position vector contains NaNs');
            
            obj.moveAxesWithBacklashCompensation(val);
        end
        
        function stop(obj)
            for idx = 1:numel(obj.hMotors)
                try
                    if obj.hMotors{idx}.initSuccessful
                        obj.hMotors{idx}.stop();
                    end
                catch ME
                    most.ErrorHandler.logAndReportError(ME,sprintf('Motor %s threw an error when attempting to stop move.',obj.hMotors{idx}.name));
                end
            end
        end
    end
    
    methods (Hidden)
        function moveAxesWithBacklashCompensation(obj,axesXYZ)
            if any(obj.backlashCompensation)
                currentXYZ = obj.queryPosition();
                moveDirection = sign(axesXYZ-currentXYZ);
                applyCompensation = moveDirection ~= sign(obj.backlashCompensation);
                
                if any(applyCompensation)
                    compensatedXYZ = axesXYZ - obj.backlashCompensation.*applyCompensation;
                    obj.moveAxes(compensatedXYZ);
                end 
            end
            
            obj.moveAxes(axesXYZ);
        end
        
        function moveAxes(obj,axesXYZ)
            % moves the motors in absolute raw XYZ units
            
            assert(~obj.errorTf,'Cannot move axes. The motor is in an error state.');
            assert(~obj.moveInProgress,'A move is already in progress');
            
            nMotors = numel(obj.hMotors);
            activeMotorMask = false(1,nMotors);
            
            for idx = 1:nMotors
                hMotor = obj.hMotors{idx};
                
                motorDimMap_ = obj.motorDimMap{idx};
                axesMask = ~isnan(motorDimMap_);
                dimIdxs = motorDimMap_(axesMask);
                
                pos = nan(1,numel(motorDimMap_));
                
                pos(axesMask) = axesXYZ(dimIdxs);
                
                if any(~isnan(pos))
                    activeMotorMask(idx) = true;
                    try
                        hMotor.moveAsync(pos);
                    catch ME
                        most.ErrorHandler.logAndReportError(ME,sprintf('Motor %s threw an error when attempting to move.',hMotor.name));
                    end
                end
            end
            
            activeMotors = obj.hMotors(activeMotorMask);
            for idx = 1:numel(activeMotors)
                try
                    activeMotors{idx}.moveWaitForFinish(obj.moveTimeout_s);
                catch ME
                    most.ErrorHandler.logAndReportError(ME,sprintf('Motor %s threw an error when attempting to wait for move to finish.',activeMotors{idx}.name));
                end
            end
            
            if any(obj.legacyMotors)
                obj.queryPosition();
            end
        end
    end
    
    %% Alignment methods
    methods
        function abortCalibration(obj)
            obj.calibrationPoints = cell(0,2);
        end
        
        function addCalibrationPoint(obj,motorPosition, motion)
            obj.queryPosition();
            
            motorPt = scanimage.mroi.coordinates.Points(obj.hCSAxesPosition,[0 0 0]);
            motorPt = motorPt.transform(obj.hCSAlignment);
            motorPt = motorPt.points;
            
            if nargin < 3 || isempty(motion)
                assert(strcmpi(obj.hSI.acqState,'focus'),'Motor alignment is only available during active Focus');
                
                if ~obj.hSI.hMotionManager.enable                    
                    obj.hSI.hMotionManager.activateMotionCorrectionSimple();
                end
                
                assert(~isempty(obj.hSI.hMotionManager.motionHistory),'Motion History is empty.');
                motion = obj.hSI.hMotionManager.motionHistory(end).drRef(1:2);
                motion = scanimage.mroi.coordinates.Points(obj.hSI.hCoordinateSystems.hCSReference,[motion 0]);
                motion = motion.transform(obj.hCSAlignment.hParent);
                motion = motion.points(1:2);
            end
            
            obj.calibrationPoints(end+1,:) = {motorPt, motion};
            
            pts = vertcat(obj.calibrationPoints{:,1});
            d = max(pts(:,3:end),[],1)-min(pts(:,3:end),[],1);
            
            if any(d > 1)
                warning('Motor alignment points are taken at different z depths. For best results, do not move the z stage during motor calibration');
            end
        end
        
        function createCalibrationMatrix(obj)
            assert(size(obj.calibrationPoints,1)>=3,'At least three calibration Points are needed to perform the calibration');
            
            motorPoints = vertcat(obj.calibrationPoints{:,1});
            if size(motorPoints,2) >= 3
                assert(all(abs(motorPoints(:,3)-motorPoints(1,3)) < 1),'All calibration points need to be taken on the same z plane and at the same rotation');
            end
            
            motorPoints = motorPoints(:,1:2);
            
            motionPoints = obj.calibrationPoints(:,2);
            motionPoints = vertcat(motionPoints{:});
            
            motorPoints(:,3) = 1;
            motionPoints(:,3) = 1;
            
            T = motionPoints' * pinv(motorPoints');
            T([3,6,7,8]) = 0;
            T(9) = 1;
            T = scanimage.mroi.util.affine2Dto3D(T);
            
            obj.abortCalibration();
            obj.hCSAlignment.toParentAffine = T;
        end
        
        function resetCalibrationMatrix(obj)
            obj.hCSAlignment.reset();
        end
        
         function correctObjectiveResolution(obj)            
            T = obj.hCSAlignment.toParentAffine;
            
            if isequal(T,eye(size(T,1)))
                error('Run the motor alignment first to obtain info about the objective resolution');
            end
            
            pts = [0 0 0;
                   1 1 0];
            
            Pts = scanimage.mroi.coordinates.Points(obj.hCSSampleRelative,pts);
            Pts = Pts.transform(obj.hSI.hCoordinateSystems.hCSReference);
            pts = Pts.points;
            v = pts(2,:)-pts(1,:);
            v = abs(v);
            
            aspectRatio = v(1)/v(2);
            if aspectRatio < 0.95 || aspectRatio > 1.05
                error('The scan aspect ratio (X/Y) is %.2f\nFix the mirror settings in the machine configuration to achieve a scan with an aspect ration of 1, then rerun the calibration.',aspectRatio);
            end
            
            degPerUm = (v(1)+v(2))/2;
            umPerDeg = 1/degPerUm;
            
            obj.hSI.objectiveResolution = umPerDeg;
            
            msg = sprintf('New Objective Resolution: %.2f um/deg',umPerDeg);
            msgbox(msg, 'Resolution update','help');
        end
    end
    
    %% User defined positions
    methods
        function defineUserPosition(obj,name,posn)
            % defineUserPosition   add current motor position, or specified posn, to
            %   motorUserDefinedPositions array at specified idx
            %
            %   obj.defineUserPosition()          add current position to list of user positions
            %   obj.defineUserPosition(name)      add current position to list of user positions, assign name
            %   obj.defineUserPosition(name,posn) add posn to list of user positions, assign name
            
            if nargin < 2 || isempty(name)
                name = '';
            end
            if nargin < 3 || isempty(posn)
                obj.queryPosition();
                posn = obj.samplePosition;
            end
            obj.userDefinedPositions(end+1) = struct('name',name,'coords',posn);
        end
        
        function clearUserDefinedPositions(obj)
        % clearUserDefinedPositions  Clears all user-defined positions
        %
        %   obj.clearUserDefinedPositions()   returns nothing
        
            obj.userDefinedPositions = repmat(struct('name','','coords',[]),0,1);
        end
        
        function gotoUserDefinedPosition(obj,posn)
            % gotoUserDefinedPosition   move motors to user defined position
            %
            %   obj.gotoUserDefinedPosition(posn)  move motor to posn, where posn is either the name or the index of a position
            
            %Move motor to stored position coordinates
            if ischar(posn)
                posn = ismember(posn, {obj.userDefinedPositions.name});
            end
            assert(posn > 0 && numel(obj.userDefinedPositions) >= posn, 'Invalid position selection.');
            obj.moveSample(obj.userDefinedPositions(posn).coords);
        end
        
        function saveUserDefinedPositions(obj)
            % saveUserDefinedPositions  Save contents of motorUserDefinedPositions array to a position (.POS) file
            %
            %   obj.saveUserDefinedPositions()  opens file dialog and saves user positions to selected file
            
            if obj.componentExecuteFunction('motorSaveUserDefinedPositions')
                [fname, pname]=uiputfile('*.pos', 'Choose position list file'); % TODO starting path
                if ~isnumeric(fname)
                    periods=strfind(fname, '.');
                    if any(periods)
                        fname=fname(1:periods(1)-1);
                    end
                    s.userDefinedPositions = obj.userDefinedPositions; %#ok<STRNU>
                    save(fullfile(pname, [fname '.pos']),'-struct','s','-mat');
                end
            end
        end
        
        function loadUserDefinedPositions(obj)
            % loadUserDefinedPositions  loads contents of a position (.POS) file to the motorUserDefinedPositions array (overwriting any previous contents)
            %
            %   obj.loadUserDefinedPositions()  opens file dialog and loads user positions from selected file
            if obj.componentExecuteFunction('motorLoadUserDefinedPositions')
                [fname, pname]=uigetfile('*.pos', 'Choose position list file');
                if ~isnumeric(fname)
                    periods=strfind(fname,'.');
                    if any(periods)
                        fname=fname(1:periods(1)-1);
                    end
                    s = load(fullfile(pname, [fname '.pos']), '-mat');
                    obj.userDefinedPositions = s.userDefinedPositions;
                end
            end
        end
    end
    
    %% Property Getter/Setter
    methods
        function set.userDefinedPositions(obj,val)
            assert(all(isfield(val,{'name' 'coords'})), 'Invalid setting for userDefinedPositions');
            obj.userDefinedPositions = val;
        end
        
        function val = get.isAligned(obj)
            tPA = obj.hCSAlignment.toParentAffine;
            fPA = obj.hCSAlignment.fromParentAffine;
            
            val = ~isIdentity(tPA) || ~isIdentity(fPA);
            
            function tf = isIdentity(T)
                I = eye(size(T,1),class(T));
                tf = isequal(I,T);
            end
        end
        
        function val = get.isRelativeZeroSet(obj)
            isIdentity = isequal(obj.hCSStageRelative.toParentAffine,eye(4)) || isequal(obj.hCSStageRelative.fromParentAffine,eye(4));
            val = ~isIdentity;
        end
        
        function set.isRelativeZeroSet(obj,val)
            % No op, used for ui update
        end
        
        function val = get.motorPosition(obj)
            % return the objective's primary focus point in relative stage coordinates            
            hPt = obj.getPosition(obj.hCSStageRelative);
            val = hPt.points;
        end
        
        function set.motorPosition(obj,val)
            if ~obj.mdlInitialized
                return
            end
            
            if ~all(isnan(val))
               error(['Setting the motor position is not allowed. Use hSI.hMotors.moveMotor([x,y,z]) instead.' char(10) ...
                      'Note: the preferred method of moving the sample is via the new API calls' char(10) ...
                      char(9) 'position = hSI.hMotors.samplePosition' char(10) ...
                      char(9) 'hSI.hMotors.moveSample([x,y,z])']); 
            end
        end
        
        function val = get.samplePosition(obj)                
            % return the objective's primary focus point in relative stage coordinates            
            hPt = obj.getPosition(obj.hCSSampleRelative);
            val = hPt.points;
        end
        
        function set.samplePosition(obj,val)
            if ~obj.mdlInitialized
                return
            end
            
            if ~all(isnan(val))
                error('Setting the sample position is not allowed. Use hSI.hMotors.moveSample([x,y,z]) instead.');
            end
        end
        
        function val = get.moveInProgress(obj)
            if isempty(obj.hMotors)
                val = false;
            else
                val = false(1,numel(obj.hMotors));
                for idx = 1:numel(obj.hMotors)
                    try
                        val(idx) = obj.hMotors{idx}.isMoving;
                    catch ME
                        most.ErrorHandler.logAndReportError(ME,sprintf('Motor %s threw an error when attempting to retrieve property moveInProgress.',obj.hMotors{idx}.name));
                    end
                end
                val = any(val);
            end
        end
        
        function set.moveInProgress(obj,val)
            % No-op, used for UI update only
        end
        
        function val = get.axesPosition(obj)
            val = obj.hCSAxesPosition.fromParentAffine(13:15);
        end
        
        function set.axesPosition(obj,val)
            % No-op, used for UI update only
        end
        
        function val = get.errorMsg(obj)
            nMotors = numel(obj.hMotors);
            val = cell(1,nMotors);
            for idx = 1:nMotors
                try
                    val{idx} = obj.hMotors{idx}.errorMsg;
                catch ME
                    most.ErrorHandler.logAndReportError(ME,sprintf('Motor %s threw an error when attempting to read motor''s error status.',obj.hMotors{idx}.name));
                end
            end
        end
        
        function set.errorMsg(obj,val)
            % No-op, used for UI update only
            obj.errorTf = NaN;
        end
        
        function val = get.errorTf(obj)
            val = any(cellfun(@(e)~isempty(e),obj.errorMsg));
        end
        
        function set.errorTf(obj,val)
            % No-op used for UI update only
        end
        
        function set.hErrorCallBack(obj,val)
            if isempty(val)
                val = function_handle.empty(0,1);
            else
                validateattributes(val,{'function_handle'},{'scalar'});
            end
            
            obj.hErrorCallBack = val;
        end
        
        function set.azimuth(obj,val)
            if isnan(val)
                return % used for UI update
            end
            
            val = obj.validatePropArg('azimuth',val);
            
            % rotation around z axis => yaw
            [yaw,pitch,roll] = obj.getRotationAngles();
            yaw = val * pi/180;
            obj.setRotationAngles(yaw,pitch,roll);
        end
        
        function val = get.azimuth(obj)
            [yaw,pitch,roll] = obj.getRotationAngles();
            val = yaw * 180/pi;
        end
        
        function set.elevation(obj,val)
            if isnan(val)
                return % used for UI update
            end
            
            val = obj.validatePropArg('elevation',val);
            
            % rotation around y axis => pitch
            [yaw,pitch,roll] = obj.getRotationAngles();
            pitch = val * pi/180;
            obj.setRotationAngles(yaw,pitch,roll);
        end
        
        function val = get.elevation(obj)
            [yaw,pitch,roll] = obj.getRotationAngles();
            val = pitch * 180/pi;
        end
        
        function set.backlashCompensation(obj,val)
            if isempty(val)
                val = zeros(1,3);
            end
                
            if isscalar(val)
                val = repmat(val,1,3);
            end
            
            val = obj.validatePropArg('backlashCompensation',val);
            
            obj.backlashCompensation = val(:)';
        end
    end
end

%% LOCAL
function s = initPropAttributes()
s = struct();
s.backlashCompensation = struct('Classes','numeric','Attributes',{{'numel',3,'finite','nonnan','real'}});
s.azimuth = struct('Classes','numeric','Attributes',{{'scalar','finite','nonnan','real'}});
s.elevation = struct('Classes','numeric','Attributes',{{'scalar','>=',-90,'<=',90,'finite','nonnan','real'}});
end

function s = defaultMdfSection()
    s = [...
        makeEntry('Motor used for X/Y/Z motion, including stacks.')... % comment only
        makeEntry('scaleXYZ',[1 1 1],'Defines scaling factors for axes.')...
        makeEntry('axisMovesObjective',[false false false],'Defines if XYZ axes move sample (false) or objective (true)')...
        makeEntry()... % blank line
        makeEntry('motors(1).name','','User defined name of the motor controller')...
        makeEntry('motors(1).controllerType','','If supplied, one of {''sutter.mp285'', ''sutter.mpc200'', ''thorlabs.mcm3000'', ''thorlabs.mcm5000'', ''scientifica'', ''pi.e665'', ''pi.e816'', ''npoint.lc40x'', ''bruker.MAMC''}.')...
        makeEntry('motors(1).dimensions','XYZ','Assignment of stage dimensions to SI dimensions. Can be any combination of X,Y,Z,- e.g. XY- only uses the first two axes as X and Y axes')...
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
% Motors.m                                                                 %
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
