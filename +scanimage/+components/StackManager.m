classdef StackManager < scanimage.interfaces.Component
    % StackManager
    % Manages properties and functionality for volume configurations and acquisitions

    %% USER PROPS
    properties (SetObservable)
        enable = false;
        
        stackDefinition = scanimage.types.StackDefinition.uniform;
        stackMode       = scanimage.types.StackMode.slow;
        stackActuator   = scanimage.types.StackActuator.motor;
        stackFastWaveformType = scanimage.types.StackFastWaveformType.sawtooth;
        
        % uniform stack definition
        stackZStepSize=1;                   % distance in microns to travel for each stack step. Used for slow stack and FastZ volumes
        
        % uniform and bounded stack definition
        framesPerSlice = 1;                 % Number of frames to acquire at each z-depth during each acquistion for a slow stack
        numSlices = 1;                      % Number of independent z-depths to image during each acquisition
        numVolumes = 1;                     % Number of volumes to acquire
        useStartEndPowers = true;           % Bounded stack: If true, use start and end powers

        % arbitrary stack definitions
        arbitraryZs = [0 1];
        
        % general properties
        stackReturnHome=true;               % if true, motor returns to original z-position after stack
        centeredStack=false;                % if true, the current z-position is considered the stack center rather than the stack beginning.
        closeShutterBetweenSlices = false;  % if true, shutter closes between slices in a slow stack
    end
    
    properties (SetObservable, Dependent, Transient)
        actualNumSlices;                    % num slices for current configuration
        actualNumVolumes;                   % num volumes for current configuration
        actualStackZStepSize;               % step size in microns between slices
        
        stackZStartPos;                     % start position for stack in bounded mode in relative sample coordinates
        stackZEndPos;                       % end   position for stack in bounded mode in relative sample coordinates
    end
    
    properties (SetObservable, SetAccess = private)
        zPowerReference = 0;                % z, where the beam power was defined. This z is regarded as point 0 for pzAdjust
        zs = 0;                             % Array of z depths for stack in relative sample coordinates
        zsRelative = 0;                     % Array of z depths for stack in reference space coordinates
    end
    
    properties (SetObservable, SetAccess = private, Hidden)
        hZs = [];                           % Array of z depths for stack in absolute sample coordinates
        hZPowerReference = [];
        
        hStackZStartPos=[];                 % start position for stack in bounded mode in absolute sample coordinates
        hStackZEndPos=[];                   % end   position for stack in bounded mode in absolute sample coordinates
    end
    
    properties (SetObservable, SetAccess = private, Transient)
        stackStartPower = [];              % bounded stack start power
        stackEndPower = [];                % bounded stack end power
    end
    
    properties (SetObservable, AbortSet, Transient)
        volumesDone = 0;                    % status indicator: number of volumes completed in current acquisition
        slicesDone  = 0;                    % status indicator: number of slices  completed in current volume
        framesDone  = 0;                    % status indicator: number of frames  completed in current slice
    end
    
	properties (SetAccess = private, Hidden)
		zSeriesLocked = false;              % prevents z-series from updating
        homePosition;                       % cached home position to return to at end of stack in absolute sample coordinates
        beamHomePower;                      
    end
    
    properties (SetObservable, Dependent, Transient)
        numFramesPerVolume;
        numFramesPerVolumeWithFlyback;
    end
    
    %% FRIEND PROPS
    properties (SetObservable, Dependent, Hidden)
        isFastZAvailable;
        overrideLZs;
    end
    
    %% INTERNAL PROPS
    %%% ABSTRACT PROPERTY REALIZATION (most.Model)
    properties (Hidden,SetAccess=protected)
        mdlPropAttributes = ziniInitPropAttributes();
        mdlHeaderExcludeProps = {'volumesDone','slicesDone','framesDone'};
    end
    
    %%% ABSTRACT PROPERTY REALIZATION (scanimage.interfaces.Component)
    properties (SetAccess = protected, Hidden)
        numInstances = 1;                   % StackManager manages FastZ and Motors. 
    end
    
    properties (Constant, Hidden)
        COMPONENT_NAME = 'StackManager';                 % [char array] short name describing functionality of component e.g. 'Beams' or 'FastZ'
        PROP_TRUE_LIVE_UPDATE = {};                      % Cell array of strings specifying properties that can be set while the component is active
        PROP_FOCUS_TRUE_LIVE_UPDATE = {'hStackZStartPos','hStackZEndPos','stackReturnHome','stackZStepSize','stackDefinition','stackMode','stackActuator','stackFastWaveformType','closeShutterBetweenSlices','centeredStack'};                % Cell array of strings specifying properties that can be set while focusing
        DENY_PROP_LIVE_UPDATE = {'enable','framesPerSlice','numSlices','numVolumes'}; % Cell array of strings specifying properties for which a live update is denied (during acqState = Focus)
        FUNC_TRUE_LIVE_EXECUTION = {};                   % Cell array of strings specifying functions that can be executed while the component is active
        FUNC_FOCUS_TRUE_LIVE_EXECUTION = {};             % Cell array of strings specifying functions that can be executed while focusing
        DENY_FUNC_LIVE_EXECUTION = {};                   % Cell array of strings specifying functions for which a live execution is denied (during acqState = Focus)
    end
    
    properties (Hidden, SetAccess=private)
        hMtrListener;
    end

    properties (Hidden, Dependent)
        isSlowZ;                            % logical; if true, current props specify a slow stack acquisition on GRAB/LOOP
        isFastZ;                            % logical; if true, current props specify a fast stack acquisition on GRAB/LOOP
        stackStartEndPointsDefined;         % logical; if true, stackZStartPos, stackZEndPos are defined (non-nan)
        
        hCSBackend
        hCSDisplay
    end
    
    %% LIFECYCLE
    methods
        function obj = StackManager(hSI)
            obj = obj@scanimage.interfaces.Component(hSI);
        end
        
        function delete(obj)
            delete(obj.hMtrListener);
        end
    end
    
    methods (Access = protected, Hidden)
        function mdlInitialize(obj)
            mdlInitialize@most.Model(obj);
            obj.hMtrListener = most.ErrorHandler.addCatchingListener(obj.hSI.hMotors,'motorPosition','PostSet',@(varargin)obj.motorPosChanged);
            obj.updateZSeries();
        end
    end
    
    %% USER METHODS
    methods
        function setStackStart(obj)
            obj.hSI.hMotors.queryPosition();
            hPt = obj.getFocalPoint();
            
            obj.stackStartPower = obj.hSI.hBeams.powers;
            obj.hStackZStartPos = hPt;
        end
        
        function clearStackStart(obj)
            obj.stackStartPower = [];
            obj.hStackZStartPos = [];
            
            obj.updateZSeries();
        end
        
        function setStackEnd(obj)
            obj.hSI.hMotors.queryPosition();
            hPt = obj.getFocalPoint();
            
            obj.stackEndPower = obj.hSI.hBeams.powers;
            obj.hStackZEndPos = hPt;
        end
        
        function clearStackEnd(obj)
            obj.stackEndPower = [];
            obj.hStackZEndPos = [];
            
            obj.updateZSeries();
        end
    end
    
    %% FRIEND METHODS
    methods (Hidden)   
        function hPt = getFocalPoint(obj)
            hPt = scanimage.mroi.coordinates.Points(obj.hSI.hCoordinateSystems.hCSFocus,[0 0 0]);
            hPt = hPt.transform(obj.hCSBackend);
        end
        
        function resetHome(obj)
            obj.homePosition = [];
            obj.beamHomePower = [];
        end
        
        function setHome(obj)
            obj.homePosition = obj.getFocusPosition();
            obj.beamHomePower = obj.hSI.hBeams.powers;
        end
        
        function goHome(obj)
            if ~isempty(obj.homePosition)
                obj.setFocusPosition(obj.homePosition,obj.stackActuator);
            end
            
            if ~isempty(obj.beamHomePower)
                obj.hSI.hBeams.powers = obj.beamHomePower;
            end
        end
        
        function motorPosChanged(obj)
            obj.updateZSeries();
        end
        
        function updateZSeries(obj)
            if ~obj.mdlInitialized || obj.zSeriesLocked
                return
            end
            
            hPtFocus = obj.getFocalPoint();            
            obj.hZPowerReference = hPtFocus;
            
            if obj.hSI.hRoiManager.isLineScan
                obj.hZs = hPtFocus;
                return
            end 
            
            if ~obj.enable
                obj.hZs = hPtFocus;
                return
            end
            
            switch obj.stackDefinition
                case scanimage.types.StackDefinition.bounded
                    updateZSeriesBounded();
                case scanimage.types.StackDefinition.uniform
                    updateZSeriesUniform();
                case scanimage.types.StackDefinition.arbitrary
                    updateZSeriesArbitrary();
                otherwise
                    error('Unknown stacktype: %s',obj.stackDefinition);
            end
            
            %%% Nested functions
            function updateZSeriesBounded()                
                if isempty(obj.hStackZStartPos)
                    hStartZ = [];
                    startZ = [];
                else
                    hStartZ = obj.hStackZStartPos.transform(obj.hCSBackend);
                    startZ = hStartZ.points(3);
                end
                
                if isempty(obj.hStackZEndPos)
                    endZ = [];
                else
                    endZ = obj.hStackZEndPos.transform(obj.hCSBackend);
                    endZ = endZ.points(3);
                end
                
                if isempty(startZ) && isempty(endZ)
                    zs_ = hPtFocus.points(3);
                elseif isempty(endZ)
                    zs_ = startZ;
                elseif isempty(startZ)
                    zs_ = endZ;
                else
                    zs_ = linspace(startZ,endZ,obj.numSlices);
                end
                
                if obj.useStartEndPowers && ~isempty(hStartZ)
                   obj.hZPowerReference = hStartZ;
                end
                
                zs_ = replicateZsForMultipleFramesPerSlice(zs_);
                
                points = zeros(numel(zs_),3);
                points(:,3) = zs_;
                
                obj.hZs = scanimage.mroi.coordinates.Points(obj.hCSBackend,points);
            end
            
            function updateZSeriesUniform()
                startZ = hPtFocus.points(3);
                extent = (obj.numSlices-1) * obj.stackZStepSize;
                
                zs_ = linspace(0,1,obj.numSlices);
                
                if obj.centeredStack
                    zs_ = zs_-0.5;
                end
                
                zs_ = startZ + zs_*extent;
                zs_ = replicateZsForMultipleFramesPerSlice(zs_);
                
                points = zeros(numel(zs_),3);
                points(:,3) = zs_;
                
                obj.hZs = scanimage.mroi.coordinates.Points(obj.hCSBackend,points);
            end
            
            function updateZSeriesArbitrary()
                zs_ = obj.arbitraryZs;
                zs_ = replicateZsForMultipleFramesPerSlice(zs_);
                
                points = zeros(numel(zs_),3);
                points(:,3) = zs_;
                
                hZs_ = scanimage.mroi.coordinates.Points(obj.hSI.hCoordinateSystems.hCSSampleRelative,points);
                obj.hZs = hZs_.transform(obj.hCSBackend);
            end
            
            function zs = replicateZsForMultipleFramesPerSlice(zs)
                if ~isinf(obj.framesPerSlice)
                    zs = repmat(zs(:)',obj.framesPerSlice,1);
                    zs = zs(:)';
                end
            end
        end
        
        function transformZs(obj)
            if isempty(obj.hZs)
                obj.zs = 0; % this happens during startup only
                obj.zsRelative = 0;
            else
                hPts = obj.hZs.transform(obj.hCSDisplay);
                obj.zs = round( hPts.points(:,3)', scanimage.constants.ROIs.zDecimalDigits);
                
                hPts = obj.hZs.transform(obj.hSI.hCoordinateSystems.hCSReference);
                zsReferenceSpace = round( hPts.points(:,3)', scanimage.constants.ROIs.zDecimalDigits);
                
                hPts = obj.getFocalPoint();
                hPts = hPts.transform(obj.hSI.hCoordinateSystems.hCSReference);
                focalPtReferencSpace = round( hPts.points(:,3)', scanimage.constants.ROIs.zDecimalDigits);
                
                % zsRelative is the z series for the FastZ actuator
                if obj.enable
                    switch obj.stackMode
                        case scanimage.types.StackMode.slow
                            switch obj.stackActuator
                                case scanimage.types.StackActuator.fastZ
                                    obj.zsRelative = zsReferenceSpace;
                                otherwise
                                    obj.zsRelative = repmat(focalPtReferencSpace,1,numel(obj.zs));
                            end
                            
                        case scanimage.types.StackMode.fast
                            obj.zsRelative = zsReferenceSpace;
                            
                        otherwise
                            error('Unknown stackmode: %s',obj.stackMode);
                    end
                    
                else
                    obj.zsRelative = focalPtReferencSpace;
                end
            end
        end
        
        function stripeData = stripeAcquired(obj,stripeData)
            if ~stripeData.endOfFrame
                return
            end
            
            frameNumberAcq = stripeData.frameNumberAcq(end);
            
            if isnan(stripeData.zIdx)
                return; % flyback frame
            end
            
            if obj.isFastZ
                obj.volumesDone = floor(frameNumberAcq/obj.numFramesPerVolumeWithFlyback);
                slicesDone_ = floor(stripeData.zIdx/obj.framesPerSlice);
                obj.slicesDone = slicesDone_ * (slicesDone_ ~= obj.actualNumSlices);
                obj.framesDone   = mod(stripeData.zIdx,obj.framesPerSlice);
            elseif obj.isSlowZ
                % all frames in one acquisition belong to the same slice
                obj.framesDone = frameNumberAcq;
            else
                obj.framesDone  = frameNumberAcq;
                obj.slicesDone  = 0;
                obj.volumesDone = 0;
            end
        end
        
        function stackDone = endOfAcquisition(obj)                
            if obj.isSlowZ
                obj.framesDone = 0;
                slicesDone_ = obj.slicesDone+1;
                if slicesDone_ == obj.actualNumSlices
                    obj.volumesDone = obj.volumesDone + 1;
                    slicesDone_ = 0;
                end
                obj.slicesDone = slicesDone_;
                stackDone = obj.volumesDone >= obj.numVolumes;
                
                transitionShutter(false);
                
                obj.hSI.hUserFunctions.notify('sliceDone');
                if ~stackDone
                    nextZIdx = obj.slicesDone*obj.framesPerSlice+1;
                    nextZIdx = mod(nextZIdx-1,numel(obj.hZs.points))+1;
                    nextZ = obj.hZs.subset(nextZIdx);
                    obj.setFocusPosition(nextZ,obj.stackActuator);
                    obj.updateStackData();
                    
                    transitionShutter(true);
                    
                    obj.hSI.hScan2D.trigIssueSoftwareAcq();
                end
            else
                stackDone = true;
            end
            
            %%% nested function
            function transitionShutter(tf)
                if obj.closeShutterBetweenSlices
                    shutterIDs = obj.hSI.hScan2D.mdfData.shutterIDs;
                    applyShutterOpenTime = tf;
                    obj.hSI.hShutters.shuttersTransition(shutterIDs,tf,applyShutterOpenTime);
                end
            end
        end
        
        function updateStackData(obj)
            %Update AOs for next slice
            obj.hSI.hWaveformManager.updateWaveforms();
            obj.hSI.hScan2D.updateSliceAO();
            obj.hSI.hBeams.updateSliceAO();
            obj.hSI.hFastZ.updateSliceAO();
        end
        
        function stripeData = stripeDataCalcZ(obj,stripeData)
            assert(~isempty(stripeData.frameNumberAcq));
            
            if obj.isSlowZ
                sliceFramesDone = obj.slicesDone*obj.framesPerSlice;
                zIdx = sliceFramesDone + stripeData.frameNumberAcq;
            else
                zIdx = mod(stripeData.frameNumberAcq-1,obj.numFramesPerVolumeWithFlyback)+1;
                if zIdx > obj.numFramesPerVolume
                    zIdx = NaN;
                end
            end
            
            stripeData.startOfVolume = zIdx == 1;
            stripeData.endOfVolume   = zIdx == obj.numFramesPerVolume;
            stripeData.zIdx = zIdx;
            stripeData.zSeries = obj.zs;
        end
        
        function val = getFocusPosition(obj)
            hFocus = scanimage.mroi.coordinates.Points(obj.hSI.hCoordinateSystems.hCSFocus,[0,0,0]);
            val = hFocus.transform(obj.hCSBackend);
        end
        
        function setFocusPosition(obj,val,actuator)
            assert(isa(val,'scanimage.mroi.coordinates.Points'));
            assert(val.numPoints==1);
            assert(isa(actuator,'scanimage.types.StackActuator'));
            
            switch actuator
                case scanimage.types.StackActuator.motor
                    hFocus = scanimage.mroi.coordinates.Points(obj.hSI.hCoordinateSystems.hCSFocus,[0 0 0]);
                    hFocus = hFocus.transform(obj.hSI.hCoordinateSystems.hCSSampleRelative);
                    val = val.transform(obj.hSI.hCoordinateSystems.hCSSampleRelative);
                    newZ = val.points(3) + obj.hSI.hMotors.samplePosition(3) - hFocus.points(3);;
                    obj.hSI.hMotors.moveSample([NaN NaN newZ]);
                case scanimage.types.StackActuator.fastZ
                    if obj.isFastZAvailable
                        val = val.transform(obj.hSI.hCoordinateSystems.hCSFocus);
                        obj.hSI.hFastZ.positionTarget = obj.hSI.hFastZ.positionTarget+val.points(1,3);
                    end
                otherwise
                    error('Unknown stack actuator: %s',obj.stackActuator);
            end
        end
    end
    
    %% INTERNAL METHODS 
    methods (Access = protected, Hidden)
        function componentStart(obj)            
            obj.updateZSeries(); % Recompute zseries
			obj.zSeriesLocked = true;
            
            obj.setHome();
            
            % reset counters
            obj.volumesDone = 0;
            obj.slicesDone  = 0;
            obj.framesDone  = 0;
            
            if obj.hSI.hRoiManager.isLineScan
                assert(~obj.enable,'Line scanning does not support stack acquisition. Disable stack acquistion and retry.');
            end
            
            if obj.isSlowZ
                configureSlowZ();
            elseif obj.isFastZ
                configureFastZ();
            else
                configureNoStack();
            end
            
            %%%%%%%%%%%%%%%%%%%%% Nested functions %%%%%%%%%%%%%%%%%%%%%%%%
            function configureNoStack()
                obj.hSI.hFastZ.enable = false;
                
                % configure Scan2D
                obj.hSI.hScan2D.framesPerAcq        = obj.framesPerSlice;
                obj.hSI.hScan2D.trigAcqNumRepeats   = obj.hSI.acqsPerLoop;
                obj.hSI.hScan2D.logSlowStack        = false;  % boolean, if true, multiple acqs are appended into single file
                obj.hSI.hScan2D.logNumSlices        = 1;      % number of acqs to append
                obj.hSI.hScan2D.framesPerStack      = obj.numFramesPerVolumeWithFlyback;
                obj.hSI.hScan2D.framesPerStack      = obj.numFramesPerVolumeWithFlyback;
                obj.hSI.hScan2D.trigAcqTypeExternal = obj.hSI.extTrigEnable;
            end
            
            function configureSlowZ()
                assert(~obj.hSI.extTrigEnable,'SlowZ stacks with external triggering are currently not supported.');
                validateBoundedStack();
                
                % move to start of stack
                switch obj.stackActuator
                    case scanimage.types.StackActuator.fastZ
                        assertFastZAvailable();
                    case scanimage.types.StackActuator.motor
                        % no-op
                    otherwise
                        error('Unknown stack actuator: %s',obj.stackActuator);
                end
                
                obj.setFocusPosition(obj.hZs.subset(1),obj.stackActuator);
                
                obj.hSI.hFastZ.enable = false;
                
                % configure Scan2D
                obj.hSI.hScan2D.framesPerAcq        = obj.framesPerSlice;
                obj.hSI.hScan2D.trigAcqNumRepeats   = obj.actualNumSlices * obj.numVolumes;
                obj.hSI.hScan2D.logSlowStack        = true;              % boolean, if true, multiple acqs are appended into single file
                obj.hSI.hScan2D.logNumSlices        = obj.actualNumSlices * obj.actualNumVolumes;  % number of acqs to append
                obj.hSI.hScan2D.framesPerStack      = 1;
                obj.hSI.hScan2D.trigAcqTypeExternal = obj.hSI.extTrigEnable;
            end
            
            function configureFastZ()
                %%% validate configuration
                assert(obj.stackActuator == scanimage.types.StackActuator.fastZ,'Incorrect Actuator setting for FastZ'); % sanity check
                
                if obj.stackDefinition == scanimage.types.StackDefinition.arbitrary && obj.actualNumSlices > 1
                    assert(obj.stackFastWaveformType == scanimage.types.StackFastWaveformType.step,...
                        'For arbitrary fast stacks, the waveform type must be set to ''step''.');
                end
                
                if obj.framesPerSlice > 1 && obj.actualNumSlices > 1
                    assert(obj.stackFastWaveformType == scanimage.types.StackFastWaveformType.step,...
                        'For fast stacks with multiple frames per slice, the waveform type must be set to ''step''.');
                end
                
                validateBoundedStack();
                assertFastZAvailable();
                
                %%% configure system
                obj.hSI.hFastZ.enable = true;
                
                % move to start of stack
                obj.setFocusPosition(obj.hZs.subset(1),scanimage.types.StackActuator.fastZ);
                
                % configure Scan2D
                obj.hSI.hScan2D.framesPerAcq        = obj.numFramesPerVolumeWithFlyback * obj.numVolumes;
                obj.hSI.hScan2D.trigAcqNumRepeats   = obj.hSI.acqsPerLoop;
                obj.hSI.hScan2D.logSlowStack        = false;  % boolean, if true, multiple acqs are appended into single file
                obj.hSI.hScan2D.logNumSlices        = 1;      % number of acqs to append
                obj.hSI.hScan2D.framesPerStack      = obj.numFramesPerVolumeWithFlyback;
                obj.hSI.hScan2D.trigAcqTypeExternal = obj.hSI.extTrigEnable;
            end
            
            function assertFastZAvailable()
                assert(obj.isFastZAvailable,'Cannot acquire a FastZ stack since no FastZ actuator is available for %s',obj.hSI.hScan2D.name);    
            end
            
            function validateBoundedStack()
                if obj.stackDefinition == scanimage.types.StackDefinition.bounded
                    assert(obj.stackStartEndPointsDefined,'Both start and end positions must be set for a bounded stack');
                end
            end
        end
        
        function componentAbort(obj)            
            try
                if obj.enable && obj.stackReturnHome
                    obj.goHome();
                end
            catch ME
                most.ErrorHandler.logAndReportError(ME)
            end
            
            obj.zSeriesLocked = false;
        end
    end
    
    %% PROPERTY GETTER/SETTER
    methods
        function set.enable(obj,val)
            val = obj.validatePropArg('enable',val);
            
            if obj.componentUpdateProperty('enable',val)
                obj.enable = logical(val);
                obj.updateZSeries();
            end
        end
        
        function set.stackDefinition(obj,val)
            val = most.idioms.string2Enum(val,'scanimage.types.StackDefinition');            
            val = obj.validatePropArg('stackDefinition',val);
            
            if obj.componentUpdateProperty('stackDefinition',val)
                obj.stackDefinition = val;
            end
            
            obj.updateZSeries();
        end
        
        function set.stackMode(obj,val)
            val = most.idioms.string2Enum(val,'scanimage.types.StackMode');            
            val = obj.validatePropArg('stackMode',val);
            
            if obj.componentUpdateProperty('stackMode',val)
                obj.stackMode = val;
            end
            
            obj.updateZSeries();
        end
        
        function set.stackActuator(obj,val)
            val = most.idioms.string2Enum(val,'scanimage.types.StackActuator');            
            val = obj.validatePropArg('stackActuator',val);
            
            if obj.componentUpdateProperty('stackActuator',val)
                obj.stackActuator = val;
            end
            
            obj.updateZSeries();
        end
        
        function val = get.stackActuator(obj)
            val = obj.stackActuator;
            
            % for fast stacks, only fastZ is allowed as the actuator
            if obj.stackMode == scanimage.types.StackMode.fast
                val = scanimage.types.StackActuator.fastZ;
            end
        end
        
        function set.stackFastWaveformType(obj,val)
            val = most.idioms.string2Enum(val,'scanimage.types.StackFastWaveformType');
            val = obj.validatePropArg('stackFastWaveformType',val);
            
            if obj.componentUpdateProperty('stackFastWaveformType',val)
                obj.stackFastWaveformType = val;
            end
            
            obj.updateZSeries();
        end   
                
        function set.hStackZStartPos(obj,val)
            if isempty(val)
                val = scanimage.mroi.coordinates.Points.empty(1,0);
            else
                val = obj.validatePropArg('hStackZStartPos',val);
            end
            
            if obj.componentUpdateProperty('hStackZStartPos',val)
                obj.hStackZStartPos = val;
                obj.updateZSeries();
                obj.stackZStartPos = NaN;
            end
        end
        
        function set.stackZStartPos(obj,val)
            % No-op, for UI update only
        end
        
        function val = get.stackZStartPos(obj)
            if isempty(obj.hStackZStartPos)
                val = [];
            else
                hPt = obj.hStackZStartPos.transform(obj.hCSDisplay);
                val = hPt.points(3);
            end
        end
        
        function set.hStackZEndPos(obj,val)
            if isempty(val)
                val = scanimage.mroi.coordinates.Points.empty(1,0);
            else
                val = obj.validatePropArg('hStackZEndPos',val);
            end
            
            if obj.componentUpdateProperty('hStackZStartPos',val)
                obj.hStackZEndPos = val;
                obj.updateZSeries();
                obj.stackZEndPos = NaN;
            end
        end
        
        function set.stackZEndPos(obj,val)
            % No-op, for UI update only
        end
        
        function val = get.stackZEndPos(obj)
            if isempty(obj.hStackZEndPos)
                val = [];
            else
                hPt = obj.hStackZEndPos.transform(obj.hCSDisplay);
                val = hPt.points(3);
            end
        end
        
        function set.hZs(obj,val)
            obj.hZs = val;
            obj.transformZs();
        end
        
        function set.arbitraryZs(obj,val)
            val = obj.validatePropArg('arbitraryZs',val);
            
            if obj.componentUpdateProperty('arbitraryZs',val)
                obj.arbitraryZs = val;
            end
            
            obj.updateZSeries();
        end
        
        function set.hZPowerReference(obj,val)
            obj.hZPowerReference = val;
            obj.zPowerReference = NaN; % UI update
        end
        
        function set.zPowerReference(obj,val)
            % No op, UI update only
        end
        
        function val = get.zPowerReference(obj)
            if isempty(obj.hZPowerReference)
                val = [];
            else
                hPts = obj.hZPowerReference.transform(obj.hCSDisplay);
                val = hPts.points(:,3);
            end
        end
                
        function val = get.isFastZ(obj)
            val = obj.enable && obj.stackMode == scanimage.types.StackMode.fast;
        end
        
        function val = get.isSlowZ(obj)
            val = obj.enable && obj.stackMode == scanimage.types.StackMode.slow;
        end
        
        function set.framesPerSlice(obj,val)
            if ~isinf(val) || val < 0
                val = obj.validatePropArg('framesPerSlice',val);
            end
            
            if obj.componentUpdateProperty('framesPerSlice',val) 
                obj.framesPerSlice = val;
            end
            
            obj.updateZSeries();
        end
        
        function set.numVolumes(obj,val)
            val = obj.validatePropArg('numVolumes',val);
            
            if obj.componentUpdateProperty('numVolumes',val)
                obj.numVolumes = val;
            end
        end

        function set.numSlices(obj,val)
            val = obj.validatePropArg('numSlices',val);
            
            if obj.componentUpdateProperty('numSlices',val)
                obj.numSlices = val;
            end
            
            obj.updateZSeries();
        end
        
        function v = get.stackStartEndPointsDefined(obj)
            v = ~isempty(obj.hStackZStartPos) && ~isempty(obj.hStackZEndPos);
        end
        
        function set.stackReturnHome(obj,val)
            val = obj.validatePropArg('stackReturnHome',val);
            
            if obj.componentUpdateProperty('stackReturnHome',val)
                obj.stackReturnHome = val;
            end
        end
        
        function set.centeredStack(obj,val)
            val = obj.validatePropArg('centeredStack',val);
            
            if obj.componentUpdateProperty('centeredStack',val)
                obj.centeredStack = val;
            end
            
            obj.updateZSeries();
        end
        
        function set.stackZStepSize(obj,val)
            val = obj.validatePropArg('stackZStepSize',val);
            
            if obj.componentUpdateProperty('stackZStepSize',val)
                obj.stackZStepSize = val;
            end
            
            obj.updateZSeries();
        end
        
        function set.closeShutterBetweenSlices(obj,val)
            val = obj.validatePropArg('closeShutterBetweenSlices',val);
            
            if obj.componentUpdateProperty('closeShutterBetweenSlices')
                obj.closeShutterBetweenSlices = logical(val);
            end
        end
        
        function val = get.isFastZAvailable(obj)
            val = obj.hSI.hFastZ.hasFastZ;
        end
        
        function val = get.numFramesPerVolume(obj)
            val = numel(obj.zs);
        end
        
        function val = get.numFramesPerVolumeWithFlyback(obj)
            val = obj.numFramesPerVolume;
            
            if obj.isFastZ
                val = val + obj.hSI.hFastZ.numDiscardFlybackFrames;
            end
        end
        
        function set.actualNumSlices(obj,val)
            % No-Op UI update only
        end
        
        function val = get.actualNumSlices(obj)            
            if obj.enable
                val = numel(obj.zs) / obj.framesPerSlice;
            else
                val = 1;
            end
        end
             
        function set.actualNumVolumes(obj,val)
            % No-Op UI update only
        end
        
        function val = get.actualNumVolumes(obj)            
            if obj.enable
                val = obj.numVolumes;
            else
                val = 1;
            end
        end
        
        function set.actualStackZStepSize(obj,val)
            % No-Op UI update only
        end
        
        function val = get.actualStackZStepSize(obj)
            val = max(diff(obj.zs));
        end
        
        function val = get.hCSBackend(obj)
            val = obj.hSI.hCoordinateSystems.hCSSampleAbsolute;
        end
        
        function val = get.hCSDisplay(obj)
            val = obj.hSI.hCoordinateSystems.hCSSampleRelative;
        end
        
        function val = get.overrideLZs(obj)
            val = obj.hSI.hStackManager.enable ...
               && obj.hSI.hStackManager.stackDefinition == scanimage.types.StackDefinition.bounded ...
               && obj.hSI.hStackManager.useStartEndPowers && obj.hSI.hStackManager.stackStartEndPointsDefined;
        end
        
        function set.useStartEndPowers(obj,val)
            val = obj.validatePropArg('useStartEndPowers',val);
            
            if obj.componentUpdateProperty('useStartEndPowers')
                obj.useStartEndPowers = val;
                obj.updateZSeries();
            end
        end
    end
end

%% LOCAL
function s = ziniInitPropAttributes()
%At moment, only application props, not pass-through props, stored here -- we think this is a general rule
%NOTE: These properties are /ordered/..there may even be cases where a property is added here for purpose of ordering, without having /any/ metadata.
%       Properties are initialized/loaded in specified order.
%
s = struct();

s.zs = struct('Classes','numeric','Attributes',{{'vector'}});
s.zPowerReference = struct('Classes','numeric','Attributes',{{'scalar','nonnan','finite'}});
s.stackDefinition = struct('Classes','scanimage.types.StackDefinition','Attributes','scalar');
s.stackMode = struct('Classes','scanimage.types.StackMode','Attributes','scalar');
s.stackActuator = struct('Classes','scanimage.types.StackActuator','Attributes','scalar');
s.stackFastWaveformType = struct('Classes','scanimage.types.StackFastWaveformType','Attributes','scalar');
s.enable = struct('Classes','binaryflex','Attributes',{{'scalar','binary'}});
s.closeShutterBetweenSlices = struct('Classes','binaryflex','Attributes',{{'scalar','binary'}});
s.actualNumSlices = struct('DependsOn',{{'zs'}});
s.actualNumVolumes = struct('DependsOn',{{'numVolumes','enable'}});
s.useStartEndPowers = struct('Classes','binaryflex','Attributes',{{'scalar'}});

%%% Stack props
s.numVolumes = struct('Classes','numeric','Attributes',{{'scalar','positive','nonnan','finite','real'}});
s.numSlices = struct('Classes','numeric','Attributes',{{'scalar','positive','nonnan','finite','real'}});
s.framesPerSlice = struct('Classes','numeric','Attributes',{{'scalar' 'positive' 'integer','nonnan','real'}});
s.stackZStepSize = struct('Classes','numeric','Attributes',{{'scalar','nonnan','real'}});
s.stackReturnHome = struct('Classes','binaryflex','Attributes','scalar');
s.centeredStack = struct('Classes','binaryflex','Attributes','scalar');
s.arbitraryZs = struct('Classes','numeric','Attributes',{{'vector','finite','nonnan','real'}});
s.actualStackZStepSize = struct('DependsOn',{{'zs'}});
s.hStackZStartPos = struct('Classes','scanimage.mroi.coordinates.Points','Attributes',{{'scalar'}});
s.hStackZEndPos   = struct('Classes','scanimage.mroi.coordinates.Points','Attributes',{{'scalar'}});
end

%--------------------------------------------------------------------------%
% StackManager.m                                                           %
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
