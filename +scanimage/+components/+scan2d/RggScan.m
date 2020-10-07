classdef RggScan < scanimage.components.Scan2D & most.HasMachineDataFile
    % RggScan - subclass of Scan2D for resonantor linear scanning usingvDAQ hardware
    %   - controls a resonant(X) - galvo(X) mirror pair OR a resonant(X) - galvo(X) - galvo(Y) mirror triplet
    %   - handles the configuration of vDAQ for acquiring signal andcontrol
    %   - format PMT data into images
    %   - handles acquistion timing and acquisition state
    %   - export timing signals
    
    
    %% USER PROPS
    properties (SetObservable, Transient)
        linePhaseMode = 'Nearest Neighbor';   % Specifies method for estimating line phase if it is not measured at the current resonant amplitude
        % Note: This is all just guessing. The user must either explicitly
        % set scan phases for all zoom levels or we have to make a way for
        % the scanner to automatically set the scan phase for perfect bidi
        % alignment.
        %
        % Interpolate:      Linearly interpolate between next lower and next
        %                   higher zoom factor with a set scan phase.
        % Nearest Neighbor: Choose between scan phase of next lower and next
        %                   higher zoom factor with a set scan phase, whichever zoom factor is
        %                   closest to current.
        % Next Lower:       Choose the scan phase of the next lower zoom factor
        %                   with a set scan phase.
        % Next Higher:      Choose the scan phase of the next higher zoom factor
        %                   with a set scan phase.
        
        keepResonantScannerOn = false;  % Indicates that resonant scanner should always be on. Avoids settling time and temperature drift
        sampleRate;                     % [Hz] sample rate of the digitizer; can only be set for linear scanning
        sampleRateCtl;
        sampleRateFdbk;
        pixelBinFactor = 1;             % if objuniformSampling == true, pixelBinFactor defines the number of samples used to form a pixel
        channelOffsets;                 % Array of integer values; channelOffsets defines the dark count to be subtracted from each channel if channelsSubtractOffsets is true
    end
    
    properties (SetObservable)
        uniformSampling = false;        % [logical] defines if the same number of samples should be used to form each pixel (see also pixelBinFactor); if true, the non-uniform velocity of the resonant scanner over the field of view is not corrected
        maskDisableDivide = false;   % [logical, array] defines for each channel if averaging is enabled/disabled
        
        scanMode;
        scanModePropCache;
        stripingPeriod = 0.1;
        recordScannerFeedback = false;
    end
    
    properties (SetObservable, Transient, Dependent)
        useNonlinearResonantFov2VoltsCurve = false; % [logical] activates the LUT for correcting the aspect ratio of the resonant scanner at different zoom levels
        mask;
    end
    properties (Dependent, SetAccess = protected)
        % data that is useful for line scanning meta data
        lineScanSamplesPerFrame;
        lineScanFdbkSamplesPerFrame;
        lineScanNumFdbkChannels;
    end
    
    %% FRIEND PROPS
    properties (Hidden)
        enableContinuousFreqMeasurement = false;
        
        xGalvo;
        yGalvo;
        galvoCalibration;
        
        coercedFlybackTime;
        coercedFlytoTime;
        
        enableBenchmark = false;
        
        lastFrameAcqFcnTime = 0;
        totalFrameAcqFcnTime = 0;
        cpuFreq = 2.5e9;
        
        totalDispUpdates = 0;
        totalDispUpdateTime = 0;
        
        controllingFastZ = true;
        
        scanModePropsToCache = struct('linear',{{'sampleRate' 'pixelBinFactor' 'fillFractionSpatial' 'bidirectional' 'stripingEnable' 'linePhase'}},...
            'resonant',{{'uniformSampling' 'pixelBinFactor' 'fillFractionSpatial' 'bidirectional' 'stripingEnable'}});
        sampleRateDecim = 1;
        sampleRateCtlDecim = 100;
        ctlTimebaseRate;
        sampleRateCtlMax = 1e6;
        
        hPixListener;
        extendedRggFov;
        ctlRateGood = false;
    end
    
    properties (Hidden, Dependent)
        resonantScannerLastWrittenValue;
    end
    
    properties (Hidden)
        disableResonantZoomOutput = false;
        flagZoomChanged = false;        % (Logical) true if user changed the zoom via spinner controls.
        
        liveScannerFreq;
        lastLiveScannerFreqMeasTime;
        scanModeIsResonant;
        scanModeIsLinear;
        
        lastFramePositionData = [];
        validSampleRates;
        
        laserTriggerFilterSupport = true;
        laserTriggerDemuxSupport = true;
    end
 
    %% INTERNAL PROPS
    properties (Hidden, SetAccess = private)            
        hAcq;                               % handle to image acquisition system
        hCtl;                               % handle to galvo control system
        hTrig;                              % handle to trigger system
    end
    properties (Hidden, SetAccess = private)
        useNonlinearResonantFov2VoltsCurve_ = false;
    end
    
    properties (Hidden, SetAccess = protected, Dependent)
        linePhaseStep;                      % [s] minimum step size of the linephase
    end
    
    properties (Hidden, SetAccess = protected)
        %allowedTriggerInputTerminals;
        %allowedTriggerInputTerminalsMap;
        
        linePhase_;                     % Transient linePhase value set at current zoom; if non-empty will be stored to linePhaseMap on change of zoom or abort
        linePhaseMap;                   % containers.Map() that holds the LUT values for scan phase. Saved on acq abort to class data file.
        scanFreqMap;                    % containers.Map() that holds the LUT values for scan frequency. Saved on acq abort to class data file.
        resFov2VoltsMap;                % containers.Map() that holds the LUT values for scan angle to voltage conversion to correct for non linearity
        defaultRoiSize;
        angularRange;
        supportsRoiRotation = false;
        beamIds;
        beamDaqID;
    end
    
    %%% Abstract prop realizations (most.Model)
    properties (Hidden, SetAccess=protected)
        mdlPropAttributes = zlclAppendDependsOnPropAttributes(scanimage.components.Scan2D.scan2DPropAttributes());
        mdlHeaderExcludeProps = {'logFileStem' 'logFilePath' 'logFileCounter' 'channelsAvailableInputRanges' 'scanModePropCache'};
    end    
        
    %%% Abstract property realizations (most.HasMachineDataFile)
    properties (Constant, Hidden)
        %Value-Required properties
        mdfClassName = mfilename('class');
        mdfHeading = 'RggScan';
        
        %Value-Optional properties
        mdfDependsOnClasses; %#ok<MCCPI>
        mdfDirectProp; %#ok<MCCPI>
        mdfPropPrefix; %#ok<MCCPI>
        
        mdfDefault = defaultMdfSection();
    end
    
    %%% Abstract prop realization (scanimage.interfaces.Component)
    properties (SetAccess = protected, Hidden)
        numInstances = 0;
    end        
    
    %%% Abstract property realizations (scanimage.subystems.Scan2D)
    properties (Hidden, Constant)
        builtinFastZ = false;
    end
    
    properties (SetAccess = immutable)
        scannerType;
        hasXGalvo;                   % logical, indicates if scanner has a resonant mirror
        hasResonantMirror;           % logical, indicates if scanner has a resonant mirror
    end
    
    properties (Constant, Hidden)
        linePhaseUnits = 'seconds';
    end
    
    %%% Constants
    properties (Constant, Hidden)
        MAX_NUM_CHANNELS = 4;               % Maximum number of channels supported
        
        COMPONENT_NAME = 'RggScan';                                                     % [char array] short name describing functionality of component e.g. 'Beams' or 'FastZ'
        PROP_TRUE_LIVE_UPDATE = {...              % Cell array of strings specifying properties that can be set while the component is active
            'linePhase','logFileCounter','useNonlinearResonantFov2VoltsCurve','channelsFilter','channelsAutoReadOffsets'};
        PROP_FOCUS_TRUE_LIVE_UPDATE = {};    % Cell array of strings specifying properties that can be set while focusing
        DENY_PROP_LIVE_UPDATE = {'framesPerAcq','trigAcqTypeExternal',...  % Cell array of strings specifying properties for which a live update is denied (during acqState = Focus)
            'trigAcqTypeExternal','trigNextStopEnable','trigAcqInTerm',...
            'trigNextInTerm','trigStopInTerm','trigAcqEdge','trigNextEdge',...
            'trigStopEdge','stripeAcquiredCallback','logAverageFactor','logFilePath',...
            'logFileStem','logFramesPerFile','logFramesPerFileLock','logNumSlices'};
        
        FUNC_TRUE_LIVE_EXECUTION = {'readStripeData','trigIssueSoftwareAcq','measureScannerFrequency',...
            'trigIssueSoftwareNext','trigIssueSoftwareStop'};  % Cell array of strings specifying functions that can be executed while the component is active
        FUNC_FOCUS_TRUE_LIVE_EXECUTION = {}; % Cell array of strings specifying functions that can be executed while focusing
        DENY_FUNC_LIVE_EXECUTION = {'pointScanner','parkScanner','centerScanner','measureScannerFrequencySweep'};  % Cell array of strings specifying functions for which a live execution is denied (during acqState = Focus)
    end    
    
    %% Lifecycle
    methods
        function obj = RggScan(hSI, name)
            % RggScan constructor for scanner object
            
            obj = obj@most.HasMachineDataFile(true, ['RggScan (' name ')']);
            obj = obj@scanimage.components.Scan2D(hSI,name);
            
            %% validate mdf options
            validateattributes(obj.mdfData.galvoDeviceName,{'char'},{});
            assert(isempty(obj.mdfData.galvoDeviceName) || strcmp(obj.mdfData.galvoDeviceName,obj.mdfData.acquisitionDeviceId), 'Galvos must be controlled by same vDAQ board used for signal acquisition.');
            
            if ~isempty(obj.mdfData.galvoAOChanIDX)
                validateattributes(obj.mdfData.galvoAOChanIDX,{'numeric'},{'scalar','nonnegative'});
                validateattributes(obj.mdfData.galvoVoltsPerOpticalDegreeX,{'numeric'},{'scalar','finite'});
            end
            validateattributes(obj.mdfData.galvoAOChanIDY,{'numeric'},{'scalar','nonnegative','nonempty'});
            
            if isempty(obj.mdfData.resonantZoomDeviceName)
                obj.mdfData.resonantZoomDeviceName = obj.mdfData.galvoDeviceName;
            end
            
            if ~isempty(obj.mdfData.resonantZoomAOChanID) && ~isempty(obj.mdfData.resonantAngularRange)
                if ~isempty(obj.mdfData.resonantZoomAOChanID)
                    validateattributes(obj.mdfData.resonantZoomAOChanID,{'numeric'},{'scalar','nonnegative'});
                end
                validateattributes(obj.mdfData.resonantEnableTerminal,{'numeric','char'},{});
            end
            
            validateattributes(obj.mdfData.galvoVoltsPerOpticalDegreeY,{'numeric'},{'scalar','finite'});
            validateattributes(obj.mdfData.rScanVoltsPerOpticalDegree,{'numeric'},{'scalar','finite','positive'});
            
            validateattributes(obj.mdfData.resonantScannerSettleTime,{'numeric'},{'scalar','nonnegative','nonempty'});
            
            hBms = obj.hSI.hBeams;
            if ~isempty(obj.mdfData.beamIds)
                try
                    dqid = unique(hBms.globalID2Daq(obj.mdfData.beamIds));
                    assert(numel(dqid) == 1, 'All beams for use with ''%s'' scanner must be on scanner control vDAQ.',name);
                    dqnm = hBms.hDaqDevice{dqid};
                catch ME
                    error('Invalid beam settings.');
                end
                assert(ischar(dqnm) && strcmp(dqnm,obj.mdfData.acquisitionDeviceId), 'All beams for use with ''%s'' scanner must be on scanner control vDAQ.',name);
                obj.beamDaqID = dqid;
                obj.beamIds = obj.mdfData.beamIds;
            end
            
            %% Construct sub-components
            % Open FPGA acquisition adapter
            obj.hAcq = scanimage.components.scan2d.rggscan.Acquisition(obj,obj.simulated);
            
            % Open scanner control adapter
            obj.hCtl = scanimage.components.scan2d.rggscan.Control(obj,obj.simulated);
            
            % Open trigger routing adapter
            obj.hTrig = scanimage.components.scan2d.rggscan.Triggering(obj,obj.simulated);
            
            % Open data scope adapter
            obj.hDataScope = scanimage.components.scan2d.rggscan.DataScope(obj);
            
            obj.hasXGalvo = obj.hCtl.xGalvoExists;
            obj.hasResonantMirror = obj.hCtl.resonantMirrorExists;
            if obj.hasResonantMirror
                if obj.hasXGalvo
                    obj.scannerType = 'RGG';
                else
                    obj.scannerType = 'RG';
                end
                obj.scanMode = 'resonant';
            else
                assert(obj.hasXGalvo, 'X galvo must be present if there is no resonant mirror.');
                obj.scannerType = 'GG';
                obj.scanMode = 'linear';
            end
            
            %% Optionally define X-Galvo scanning hardware.
            if ~isempty(obj.mdfData.xGalvoAngularRange) && ~isempty(obj.mdfData.galvoAOChanIDX)
                obj.xGalvo = scanimage.mroi.scanners.Galvo();
                obj.xGalvo.name = sprintf('%s-X-Galvo',name);
                obj.xGalvo.waveformCacheBasePath = obj.hSI.hWaveformManager.waveformCacheBasePath;
                obj.xGalvo.travelRange = [-obj.mdfData.xGalvoAngularRange obj.mdfData.xGalvoAngularRange]./2;
                obj.xGalvo.voltsPerDistance = obj.mdfData.galvoVoltsPerOpticalDegreeX;
                obj.xGalvo.parkPosition = obj.mdfData.galvoParkDegreesX;
                obj.xGalvo.controlDevice = obj.hAcq.hFpga;
                obj.xGalvo.positionChannelID = obj.mdfData.galvoAOChanIDX;
                obj.xGalvo.feedbackChannelID = obj.mdfData.galvoAIChanIDX;
                v = obj.mdfData.xGalvoSlewRateLimit;
                if ~isempty(v) && ~isinf(v) && ~isnan(v)
                    obj.xGalvo.hDevice.slewRateLimit_V_per_s = v;
                    obj.xGalvo.hDevice.zeroPositionOnDelete = true;
                end
            end
            
            %% Define Y-Galvo scanning hardware.
            assert(~isempty(obj.mdfData.yGalvoAngularRange),'yGalvoAngularRange is not defined in machine data file');
            obj.yGalvo = scanimage.mroi.scanners.Galvo();
            obj.yGalvo.name = sprintf('%s-Y-Galvo',name);
            obj.yGalvo.waveformCacheBasePath = obj.hSI.hWaveformManager.waveformCacheBasePath;
            obj.yGalvo.travelRange = [-obj.mdfData.yGalvoAngularRange obj.mdfData.yGalvoAngularRange]./2;
            obj.yGalvo.voltsPerDistance = obj.mdfData.galvoVoltsPerOpticalDegreeY;
            obj.yGalvo.parkPosition = obj.mdfData.galvoParkDegreesY;
            obj.yGalvo.controlDevice = obj.hAcq.hFpga;
            obj.yGalvo.positionChannelID = obj.mdfData.galvoAOChanIDY;
            obj.yGalvo.feedbackChannelID = obj.mdfData.galvoAIChanIDY;
            v = obj.mdfData.yGalvoSlewRateLimit;
            if ~isempty(v) && ~isinf(v) && ~isnan(v)
                obj.yGalvo.hDevice.slewRateLimit_V_per_s = v;
                obj.yGalvo.hDevice.zeroPositionOnDelete = true;
            end
            
            obj.hCtl.parkGalvo();
            
            %% Init
            
            %Initialize class data file (ensure props exist in file)
            obj.zprvEnsureClassDataFileProps();
            
            %Initialize the scan maps (from values in Class Data File)
            obj.loadClassData();
            
            obj.numInstances = 1; % This has to happen _before_ any properties are set
            
            % initialize scanner frequency from mdfData
            obj.scannerFrequency = obj.mdfData.nominalResScanFreq;
            
            %Initialize sub-components
            obj.hAcq.frameAcquiredFcn = @obj.frameAcquiredFcn;            
            obj.hAcq.initialize();
            obj.hCtl.initialize();
                        
            %Initialize props (not initialized by superclass)
            obj.channelsFilter = '40 MHz';
            obj.channelsInputRanges = repmat({[-1 1]},1,obj.channelsAvailable);
            obj.channelOffsets = zeros(1, obj.channelsAvailable);
            obj.channelsSubtractOffsets = true(1, obj.channelsAvailable);
            
            if ~isempty(obj.mdfData.disableMaskDivide)
                obj.maskDisableDivide = obj.mdfData.disableMaskDivide;
            end
        end
        
        function delete(obj)
            % delete - deletes the ResScan object, parks the mirrors and
            %   deinitializes all routes
            %   obj.delete()  returns nothing
            %   delete(obj)   returns nothing
            
            obj.safeAbortDataScope();
            most.idioms.safeDeleteObj(obj.hPixListener);
            
            if obj.numInstances
                % dummy set to save calibration data
                obj.galvoCalibration = [];
            end
            
            most.idioms.safeDeleteObj(obj.xGalvo);
            most.idioms.safeDeleteObj(obj.yGalvo);
            
            most.idioms.safeDeleteObj(obj.hTrig);
            most.idioms.safeDeleteObj(obj.hCtl);
            most.idioms.safeDeleteObj(obj.hAcq);
            
            obj.saveMaps();
        end
    end
    
    %% PROP ACCESS METHODS
    methods
        function set.channelOffsets(obj,val)
            if ~isempty(val)
                Nch = obj.channelsAvailable;
                assert(numel(val) == Nch, 'Number of elements must match number of physical channels.');
                lclSubtractOffset = cast(obj.channelsSubtractOffsets,obj.channelsDataType);
                lclSubtractOffset(end+1:Nch) = lclSubtractOffset(1);
                for iter = 1:min(numel(val),numel(lclSubtractOffset))
                    fpgaVal(iter) = -val(iter) * lclSubtractOffset(iter);
                end
                obj.channelOffsets = val;
                obj.hAcq.hAcqEngine.acqParamChannelOffsets = fpgaVal;
            end
        end
        
        function set.pixelBinFactor(obj,val)
            if obj.uniformSampling || obj.scanModeIsLinear
                val = obj.validatePropArg('pixelBinFactor',val);
                if obj.componentUpdateProperty('pixelBinFactor',val)
                    obj.pixelBinFactor = val;
                    if obj.mdlInitialized
                        obj.sampleRateCtl = nan;
                    end
                end
            elseif ~ismember('RggScan.set.scanMode',arrayfun(@(s){s.name},dbstack))
                obj.errorPropertyUnSupported('pixelBinFactor',val);
            end
        end
        
        function set.sampleRate(obj,val)
            if obj.scanModeIsResonant && ~isnan(val)
                obj.errorPropertyUnSupported('sampleRate',val,'set');
                obj.sampleRateDecim = 1;
            else
                obj.sampleRateDecim = max(1,2*floor(0.5*obj.hAcq.sampleRateAcq/val));
            end
            if obj.mdlInitialized
                obj.sampleRateCtl = nan;
            end
        end
        
        function val = get.sampleRate(obj)
            val = obj.hAcq.sampleRateAcq / obj.sampleRateDecim;
        end
        
        function sf = getAllSfs(obj)
            roiGroup = obj.currentRoiGroup;
            zs = obj.hSI.hStackManager.zs;
            sf = scanimage.mroi.scanfield.fields.RotatedRectangle.empty(1,0);
            for idx = numel(zs) : -1 : 1
                zsf = roiGroup.scanFieldsAtZ(zs(idx));
                sf = [sf zsf{:}];
            end
        end
        
        function set.sampleRateCtl(obj,~)
            minDecim = ceil(obj.ctlTimebaseRate/obj.sampleRateCtlMax);
            ctlDecims = minDecim:(10*minDecim);
            
            if obj.hSI.hRoiManager.isLineScan || ~obj.scanModeIsLinear
                % for resonant scanning and arb line scanning ctl sample
                % rate doesn't really matter
                obj.sampleRateCtlDecim = min(ctlDecims);
                obj.ctlRateGood = true;
            else
                % for linear frame scanning determine a ctl rate that is
                % an integer divisor of the line period
                
                % for mroi we need to match line periods of all rois
                sf = obj.getAllSfs();
                if ~isempty(sf)
                    % start with a list of all the potential ctl sample rates
                    ctlTimebasePeriod = 1/obj.ctlTimebaseRate;
                    ctlMults = ctlDecims(:).^-1;
                    
                    % get the acq time for each scanfield
                    sfPRs = [sf.pixelResolution];
                    lineAcqPixCnts = unique(sfPRs(1:2:end));
                    lineAcqSamps = lineAcqPixCnts * obj.pixelBinFactor;
                    ff = obj.fillFractionTemporal;
                    acqSampleRate = obj.sampleRate;
                    acqSamplePeriod = 1/acqSampleRate;
                    
                    % for each sf we try a variety of line acquisition
                    % times based on varying from the desired temporal fill
                    % fraction
                    for i = 1:numel(lineAcqSamps)
                        lineAcqSampsi = lineAcqSamps(i);
                        overscanSamples = (lineAcqSampsi/ff - lineAcqSampsi)/2;
                        overscanSamples = ceil(overscanSamples:(overscanSamples*1.5));
                        linePeriods = acqSamplePeriod * (lineAcqSampsi + 2*overscanSamples);
                        
                        ctlTbPulses = (linePeriods / ctlTimebasePeriod);
                        ctlTbPulses(ctlTbPulses ~= round(ctlTbPulses)) = [];
                        
                        res = ctlMults * ctlTbPulses;
                        
                        idxs = find(res == round(res));
                        [ctlMultInds,~] = ind2sub(size(res),idxs);
                        
                        % whittle down list of valid ctl sample rates by
                        % the solutions that worked for this line acq time
                        ctlMults = ctlMults(unique(ctlMultInds));
                        
                        if isempty(ctlMults)
                            most.idioms.warn('Could not find a scanner control rate fitting the desired scan parameters. Try adjusting the acq sample rate or ROI pixel counts.');
                            obj.sampleRateCtlDecim = min(ctlDecims);
                            obj.ctlRateGood = false;
                            return;
                        end
                    end
                    
                    obj.sampleRateCtlDecim = 1/max(ctlMults);
                    obj.ctlRateGood = true;
                end
            end
        end
        
        function v = get.sampleRateFdbk(obj)
            v = obj.sampleRateCtl;
        end
        
        function v = get.ctlTimebaseRate(obj)
            if obj.scanModeIsLinear && obj.hCtl.useScannerSampleClk
                v = obj.hAcq.hFpga.nominalAcqSampleRate;
            else
                v = obj.hAcq.hFpga.waveformTimebaseRate;
            end
        end
        
        function val = get.sampleRateCtl(obj)
            val = obj.ctlTimebaseRate / obj.sampleRateCtlDecim;
        end
        
        function val = get.resonantScannerLastWrittenValue(obj)
           val = obj.hCtl.resonantScannerLastWrittenValue; 
        end
        
        function set.linePhaseStep(obj,val)
            obj.mdlDummySetProp(val,'linePhaseStep');
        end
        
        function val = get.linePhaseStep(obj)
            val = 1 / obj.sampleRate;
        end
        
        function set.linePhaseMode(obj, v)
            assert(ismember(v, {'Next Lower' 'Next Higher' 'Nearest Neighbor' 'Interpolate'}), 'Invalid choice for linePhaseMode. Must be one of {''Next Lower'' ''Next Higher'' ''Nearest Neighbor'' ''Interpolate''}.');
            obj.linePhaseMode = v;
            if obj.mdlInitialized && obj.numInstances > 0
                obj.setClassDataVar('linePhaseMode',v,obj.classDataFileName);
            end
        end
        
        function set.enableContinuousFreqMeasurement(obj, v)
            if obj.componentUpdateProperty('enableContinuousFreqMeasurement',v)
                obj.enableContinuousFreqMeasurement = v;
                
                if v && strcmp(obj.hAcq.hTimerContinuousFreqMeasurement.Running,'off')
                    start(obj.hAcq.hTimerContinuousFreqMeasurement);
                else
                    stop(obj.hAcq.hTimerContinuousFreqMeasurement);
                end
            end
        end
        
        function set.keepResonantScannerOn(obj, v)
            obj.keepResonantScannerOn = v;
            if obj.mdlInitialized && obj.numInstances > 0
                obj.setClassDataVar('keepResonantScannerOn',v,obj.classDataFileName);
                if ~obj.active
                    obj.hCtl.resonantScannerActivate(v);
                end
            end
        end
        
        function v = get.extendedRggFov(obj)
            v = obj.hasXGalvo && obj.mdfData.extendedRggFov;
        end
        
        function set.useNonlinearResonantFov2VoltsCurve(obj,v)
            v = obj.validatePropArg('useNonlinearResonantFov2VoltsCurve',v);
            if obj.componentUpdateProperty('useNonlinearResonantFov2VoltsCurve',v)
                obj.useNonlinearResonantFov2VoltsCurve_ = v;
                obj.setClassDataVar('useNonlinearResonantFov2VoltsCurve',v,obj.classDataFileName);
                if v
                    if abs((obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree) - obj.zzzResonantFov2Volts(1)) > 0.01
                        most.idioms.warn('FOV to voltage map value for FOV=1 is not consistent with mdf. Map may need to be reset.');
                    end
                end
                
                obj.updateLiveValues();
            end
        end
        
        function v = get.useNonlinearResonantFov2VoltsCurve(obj)
            v = obj.useNonlinearResonantFov2VoltsCurve_;
        end
        
        function val = get.mask(obj)
            obj.hAcq.computeMask();
            val = obj.hAcq.mask;
        end
        
        function sz = get.defaultRoiSize(obj)
            scales = abs(obj.scannerToRefTransform([1 5]));
            if obj.scanModeIsLinear
                sz = min([obj.mdfData.xGalvoAngularRange obj.mdfData.yGalvoAngularRange] .* scales);
            else
                sz = min([obj.mdfData.resonantAngularRange obj.mdfData.yGalvoAngularRange] .* scales);
            end
        end
        
        function rg = get.angularRange(obj)
            if obj.scanModeIsLinear
                x = obj.mdfData.xGalvoAngularRange;
            elseif obj.extendedRggFov
                x = obj.mdfData.xGalvoAngularRange + obj.mdfData.resonantAngularRange;
            else
                x = obj.mdfData.resonantAngularRange;
            end
            rg = [x obj.mdfData.yGalvoAngularRange];
        end
        
        function set.uniformSampling(obj,v)
            if obj.componentUpdateProperty('uniformSampling',v)
                obj.uniformSampling = v;
                obj.scanPixelTimeMean = nan;
            end
        end
        
        function set.maskDisableDivide(obj,v)
            if obj.componentUpdateProperty('maskDisableDivide',v)
                validateattributes(v,{'numeric','logical'},{'binary'});
                assert(length(v) <= obj.channelsAvailable);
                v(end+1:obj.channelsAvailable) = v(end);
                obj.maskDisableDivide = v;
                
                if ~isempty(obj.mdfData.disableMaskDivide)
                    mdf = most.MachineDataFile.getInstance();
                    if mdf.isLoaded
                        mdf.writeVarToHeading(obj.custMdfHeading,'disableMaskDivide',v);
                        obj.mdfData.disableMaskDivide = v;
                    end
                end
            end
        end
        
        function set.galvoCalibration(obj,val)
            obj.setClassDataVar('galvoCalibration',obj.galvoCalibration,obj.classDataFileName);
        end
        
        function val = get.galvoCalibration(obj)
            val = struct();
            if ~isempty(obj.xGalvo)
                val.xGalvo = obj.xGalvo.hDevice.calibrationData;
            end
            
            if ~isempty(obj.yGalvo)
                val.yGalvo = obj.yGalvo.hDevice.calibrationData;
            end
        end
        
        function v = get.coercedFlybackTime(obj)
            if obj.scanModeIsResonant
                timeDiv = obj.scannerFrequency;
            else
                timeDiv = obj.sampleRateCtl;
            end
            Nsteps = ceil(obj.flybackTimePerFrame * timeDiv);
            v = Nsteps / timeDiv;
        end
        
        function v = get.coercedFlytoTime(obj)
            if obj.scanModeIsResonant
                timeDiv = obj.scannerFrequency;
            else
                timeDiv = obj.sampleRateCtl;
            end
            Nsteps = ceil(obj.flytoTimePerScanfield * timeDiv);
            v = Nsteps / timeDiv;
        end
        
        function set.scanMode(obj,v)
            if isempty(obj.scanMode)
                obj.scanMode = v;
                obj.scanModeIsResonant = strcmp(v,'resonant');
                obj.scanModeIsLinear = ~obj.scanModeIsResonant;
            elseif obj.numInstances && ~strcmp(v,obj.scanMode)
                switch v
                    case 'resonant'
                        assert(obj.hasResonantMirror,'Scanner ''%s'' does not support resonant scanning.', obj.name);
                    case 'linear'
                        assert(obj.hasXGalvo,'Scanner ''%s'' does not support linear scanning.', obj.name);
                    otherwise
                        error('Scan mode ''%s'' is not support by scanner ''%s''.', v, obj.name);
                end
                
                % cache current setting
                prevMode = obj.scanMode;
                if isfield(obj.scanModePropsToCache, prevMode)
                    propNames = obj.scanModePropsToCache.(prevMode);
                    for i = 1:numel(propNames)
                        propName = propNames{i};
                        s.(propName) = obj.(propName);
                    end
                    obj.scanModePropCache.(prevMode) = s;
                end
                
                obj.scanMode = v;
                obj.scanModeIsResonant = strcmp(v,'resonant');
                obj.scanModeIsLinear = ~obj.scanModeIsResonant;
                if obj.scanModeIsResonant
                    obj.sampleRateDecim = 1;
                end
                
                % apply new settings
                obj.applyScanModeCachedProps();
                obj.parkScanner();
            end
        end
        
        function val = get.validSampleRates(obj)
            if obj.scanModeIsResonant
                val = obj.hAcq.sampleRateAcq;
            else
                val = obj.hAcq.sampleRateAcq ./ (6:2:1200);
            end
        end
        
        function v = get.lineScanSamplesPerFrame(obj)
            if obj.hSI.hRoiManager.isLineScan && isfield(obj.hAcq.acqParamBuffer, 'samplesPerFrame')
                v = obj.hAcq.acqParamBuffer.samplesPerFrame;
            else
                v = [];
            end
        end
        
        function v = get.lineScanFdbkSamplesPerFrame(obj)
            if obj.hSI.hRoiManager.isLineScan && isfield(obj.hAcq.acqParamBuffer, 'fdbkSamplesPerFrame')
                v = obj.hAcq.acqParamBuffer.fdbkSamplesPerFrame;
            else
                v = [];
            end
        end
        
        function v = get.lineScanNumFdbkChannels(obj)
            if obj.hSI.hRoiManager.isLineScan
                v = 2 + obj.hAcq.rec3dPath;
            else
                v = [];
            end
        end
    end
      
    %%% Abstract method implementations (scanimage.components.Scan2D)
    % AccessXXX prop API for Scan2D
    methods (Access = protected, Hidden)
        function val = accessScannersetPostGet(obj,~)
            val = obj.getScannerset(obj.scanModeIsResonant,false);
        end
        
        function accessBidirectionalPostSet(~,~)
        end
        
        function val = accessStripingEnablePreSet(obj,val)
            % unsupported in resonant scanning
            val = val && obj.scanModeIsLinear;
        end
        
        function val = accessLinePhasePreSet(obj,val)
            if obj.scanModeIsResonant && ~obj.robotMode && ~obj.flagZoomChanged && obj.mdlInitialized
                v = obj.hCtl.resonantScannerLastWrittenValue;
                
                if isempty(v) || v == 0
                    try
                        v = obj.hCtl.nextResonantVoltage;
                    catch
                    end
                end
                
                if v > 0
                    % line phase is measured in seconds
                    samples = round((val) * obj.hAcq.stateMachineLoopRate);
                    val = samples / obj.hAcq.stateMachineLoopRate ; % round to closest possible value
                    
                    %Only cache the linePhase vlaue when its values have been adjusted by the user
                    obj.linePhaseMap(round(v*1000)/1000) = val;
                end
                
            end
            obj.flagZoomChanged = false;
        end
        
        function accessLinePhasePostSet(obj)
            if obj.scanModeIsLinear
                if obj.active
                    obj.hAcq.updateBufferedPhaseSamples();
                    % regenerate beams output
                    obj.hSI.hBeams.updateBeamBufferAsync(true);
                end
            else
                obj.hAcq.fpgaUpdateLiveAcquisitionParameters('linePhaseSamples');
            end
        end
        
        function val = accessLinePhasePostGet(obj,val)
            % No-op
        end
        
        function val = accessChannelsFilterPostGet(~,val)
            % no-op
        end
        
        function val = accessChannelsFilterPreSet(obj,val)
            if ischar(val)
                if ismember(val, {'none' 'bypass' 'fbw'})
                    val = nan;
                else
                    t = regexpi(val, '(\d*)\s*MHz', 'tokens');
                    assert(~isempty(t),'Invalid filter setting.');
                    val = str2double(t{1}{1});
                end
            end
            
            assert(isnan(val) || ((val < 61) && (val > 0)), 'Invalid filter setting.');
            
            val = obj.hAcq.setChannelsFilter(val);
            
            if isnan(val)
                val = 'fbw';
            else
                val = sprintf('%d MHz',val);
            end
        end
        
        function accessBeamClockDelayPostSet(obj,~)
            if obj.scanModeIsLinear && obj.active
                obj.hSI.hBeams.updateBeamBufferAsync(true);
            end
        end
        
        function accessBeamClockExtendPostSet(obj,~)
            if obj.scanModeIsLinear && obj.active
                obj.hSI.hBeams.updateBeamBufferAsync(true);
            end
        end
        
        function accessChannelsAcquirePostSet(obj,~)
            obj.hAcq.flagResizeAcquisition = true;
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function val = accessChannelsInputRangesPreSet(obj,val)
            val = obj.hAcq.setChannelsInputRanges(val);
        end
        
        function val = accessChannelsInputRangesPostGet(~,val)
            %No-op
        end
        
        function val = accessChannelsAvailablePostGet(obj,~)
            val = obj.hAcq.adapterModuleChannelCount;
        end
        
        function val = accessChannelsAvailableInputRangesPostGet(~,~)
            val = arrayfun(@(f){[-f f]},[1 .5 .25]);
        end
                     
        function val = accessFillFractionSpatialPreSet(~,val)
        end
                     
        function accessFillFractionSpatialPostSet(obj,~)
            if obj.scanModeIsResonant
                obj.hAcq.computeMask();
            end
        end
        
        function val = accessSettleTimeFractionPostSet(obj,val)
            obj.errorPropertyUnSupported('settleTimeFraction',val);
        end
        
        function val = accessFlytoTimePerScanfieldPostGet(obj,val)
            if obj.scanModeIsResonant
                mn = 1/obj.scannerFrequency;
            else
                mn = 1/obj.sampleRateCtl;
            end
            val = max(val, mn);
        end
        
        function val = accessFlybackTimePerFramePostGet(obj,val)
            if obj.scanModeIsResonant
                mn = 1/obj.scannerFrequency;
            else
                mn = 1/obj.sampleRateCtl;
            end
            val = max(val, mn);
        end
        
        function accessLogAverageFactorPostSet(~,~)
        end
        
        function accessLogFileCounterPostSet(~,~)
        end
        
        function accessLogFilePathPostSet(~,~)
        end
        
        function accessLogFileStemPostSet(~,~)
        end
        
        function accessLogFramesPerFilePostSet(~,~)
        end

        function accessLogFramesPerFileLockPostSet(~,~)
        end
        
        function val = accessLogNumSlicesPreSet(obj,val)
            obj.hAcq.loggingNumSlices = val;
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function val = accessTrigFrameClkOutInternalTermPostGet(obj,~)
            val = obj.hTrig.sliceClkTermInt;
        end
        
        function val = accessTrigBeamClkOutInternalTermPostGet(obj,~)
            val = obj.hTrig.beamClkTermInt;
        end
        
        function val = accessTrigAcqOutInternalTermPostGet(obj,~)
            val = '';
        end
        
        function val = accessTrigReferenceClkOutInternalTermPostGet(~,~)
            val = '';
        end
        
        function val = accessTrigReferenceClkOutInternalRatePostGet(~,~)
            val = 10e6;
        end
        
        function val = accessTrigReferenceClkInInternalTermPostGet(~,~)
            val = '';
        end
        function val = accessTrigReferenceClkInInternalRatePostGet(~,~)
            val = 10e6;
        end  
        function val = accessTrigAcqInTermAllowedPostGet(obj,~) 
            val = obj.hTrig.externalTrigTerminalOptions;
        end
        
        function val = accessTrigNextInTermAllowedPostGet(obj,~)
            val = obj.hTrig.externalTrigTerminalOptions;
        end
        
        function val = accessTrigStopInTermAllowedPostGet(obj,~)
            val = obj.hTrig.externalTrigTerminalOptions;
        end
             
        function val = accessTrigAcqEdgePreSet(obj,val)    
            obj.hTrig.acqTriggerOnFallingEdge = strcmp(val,'falling');
        end
        
        function accessTrigAcqEdgePostSet(~,~)
            % Nothing to do here
        end
        
        function val = accessTrigAcqInTermPreSet(obj,val)                        
            if isempty(val)
                obj.trigAcqTypeExternal = false;
            end
            obj.hTrig.acqTriggerIn = val;
        end
        
        function accessTrigAcqInTermPostSet(~,~)
            % Nothing to do here
        end
        
        function val = accessTrigAcqInTermPostGet(obj,~)
            val = obj.hTrig.acqTriggerIn;
        end
        
        function val = accessTrigAcqTypeExternalPreSet(obj,val)
            val = logical(val); % convert 'binaryflex' to 'logcial'
        end
        
        function accessTrigAcqTypeExternalPostSet(~,~)
             %No-op        
        end
        
        function val = accessTrigNextEdgePreSet(obj,val)
            obj.hTrig.nextFileMarkerOnFallingEdge = strcmp(val,'falling');
        end
        
        function val = accessTrigNextInTermPreSet(obj,val)
            obj.hTrig.nextFileMarkerIn = val;
        end
        
        function val = accessTrigNextStopEnablePreSet(~,~)
            val = true; % the FPGA can handle Next and Stop triggering at all times. no need to deactivate it               
        end
        
        function val = accessTrigStopEdgePreSet(obj,val)
            obj.hTrig.acqStopTriggerOnFallingEdge = strcmp(val,'falling');
        end
        
        function val = accessFunctionTrigStopInTermPreSet(obj,val)
            %termName = obj.allowedTriggerInputTerminalsMap(val); % qualify terminal name (e.g. DIO0.1 -> /FPGA/DIO0.1)
            obj.hTrig.acqStopTriggerIn = val;
        end
        
        function val = accessMaxSampleRatePostGet(obj,~)
            val = max(obj.validSampleRates);
        end
        
        function accessScannerFrequencyPostSet(~,~)
            % No op
        end
        
        function val = accessScannerFrequencyPostGet(~,val)
            % No op
        end

        function val = accessScanPixelTimeMeanPostGet(obj,~)
            if ~obj.active
                obj.hAcq.bufferAllSfParams();
                obj.hAcq.computeMask();
            end
            
            if obj.scanModeIsResonant
                val = (sum(obj.hAcq.mask(1:obj.hAcq.pixelsPerLine)) / obj.sampleRate) / obj.hAcq.pixelsPerLine;
            else
                val = obj.pixelBinFactor / obj.sampleRate;
            end
        end
        
        function val = accessScanPixelTimeMaxMinRatioPostGet(obj,~)
            if isnan(obj.scanPixelTimeMean)
                val = nan;
            elseif obj.scanModeIsResonant
                maxPixelSamples = double(max(obj.hAcq.mask));
                minPixelSamples = double(min(obj.hAcq.mask));
                val = maxPixelSamples / minPixelSamples;
            else
                val = 1;
            end
        end
        
        function val = accessChannelsAdcResolutionPostGet(obj,~)
            val = obj.hAcq.ADAPTER_MODULE_ADC_BIT_DEPTH;
        end
        
        function val = accessChannelsDataTypePostGet(~,~)
            val = 'int16';
        end
        
        % Component overload function
        function val = componentGetActiveOverride(obj,~)
            val = obj.hAcq.acqRunning;
        end
        
        function val = accessScannerToRefTransformPreSet(obj,val)
            if obj.hasResonantMirror
                assert(~scanimage.mroi.util.isTransformRotating(val),'Scanner coordinate transform cannot contain rotational component.');
                assert(~scanimage.mroi.util.isTransformShearing(val),'Scanner coordinate transform cannot contain shearing component.');
                assert(~scanimage.mroi.util.isTransformPerspective(val),'Scanner coordinate transform cannot contain perspective component.');
            end
        end
        
        function accessChannelsSubtractOffsetsPostSet(obj)
            obj.channelOffsets = obj.channelOffsets; % update offsets on FPGA            
        end
    end
    
    %% USER METHODS
    
    %%% Abstract methods realizations (scanimage.interfaces.Scan2D)
    methods
        % methods to issue software triggers
        % these methods should only be effective if specified trigger type
        % is 'software'
        function trigIssueSoftwareAcq(obj)
            % trigIssueSoftwareAcq issues a software acquisition start trigger
            %   if ReScan is started, this will start an acquisition
            %   
            %   obj.trigIssueSoftwareAcq()  returns nothing
            
            if obj.componentExecuteFunction('trigIssueSoftwareAcq')
                obj.hAcq.generateSoftwareAcqTrigger();
            end
        end
        
        function trigIssueSoftwareNext(obj)
            % trigIssueSoftwareNext issues a software acquisition next trigger
            %   if ReScan is in an active acquisition, this will roll over the current acquisition
            %   
            %   obj.trigIssueSoftwareNext()  returns nothing
            
            if obj.componentExecuteFunction('trigIssueSoftwareNext')
                obj.hAcq.generateSoftwareNextFileMarkerTrigger();
            end
        end
        
        function trigIssueSoftwareStop(obj)
	        % trigIssueSoftwareStop issues a software acquisition stop trigger
            %   if ReScan is in an active acquisition, this stop the current acquisition
            %   
            %   obj.trigIssueSoftwareStop()  returns nothing
            
            if obj.componentExecuteFunction('trigIssueSoftwareStop')
                obj.hAcq.generateSoftwareAcqStopTrigger();
            end
        end
        
        function pointScanner(obj,fastDeg,slowDeg)
            % pointScanner moves the scanner to the defined angles (in degrees)
            %
            %   obj.pointScanner(fastDeg,slowDeg)   activates the resonant scanner with amplitude 'fastDeg' and points the galvo scanner to position 'slowDeg'
            %           slowDeg can be scalar (y-galvo only) or a 1x2 array [xGalvoDegree, yGalvoDegree]
            
            % points the XY scanner to a position (units: degree)
            if obj.componentExecuteFunction('pointScanner',fastDeg,slowDeg)
                obj.hCtl.pointResAmplitudeDeg(fastDeg);
                
                if isempty(obj.xGalvo)
                    obj.yGalvo.hDevice.pointPosition(slowDeg);
                else
                    validateattributes(slowDeg,{'numeric'},{'numel',2});
                    obj.xGalvo.hDevice.pointPosition(slowDeg(1));
                    obj.yGalvo.hDevice.pointPosition(slowDeg(2));
                end
            end
        end
        
        function centerScanner(obj)
            % centerScanner deactivates the resonant scanner and centers the x and y galvos
            % 
            %   obj.centerScanner()   returns nothing
            
            if obj.componentExecuteFunction('centerScanner')
                if obj.hasResonantMirror
                    obj.hCtl.pointResAmplitudeDeg(0);
                end
                obj.hCtl.centerGalvo();
            end
        end
        
        function parkScanner(obj)
            % parkScanner parks the x and y galvo scanner,
            %         deactivates resonant scanner if obj.keepResonantScannerOn == false
            %
            %   obj.parkScanner()  returns nothing
            
            if obj.componentExecuteFunction('parkScanner')
                obj.hCtl.parkGalvo();
                if obj.mdlInitialized && obj.hasResonantMirror
                    if obj.scanModeIsLinear
                        obj.hCtl.resonantScannerActivate(false);
                    elseif obj.keepResonantScannerOn && obj ~= obj.hSI.hScan2D
                        % this is to prevent an error during switching the
                        % imaging system: after switching the imaging
                        % system all scanners are parked. However, the
                        % if keepResonantScanner == true,
                        % resonantSCannerActivate queries the roiGroup to
                        % determine the next output voltage. since
                        % roiGroupDefault now spans the FOV of a
                        % different scanner, the output voltage could be
                        % out of range. In this case, don't update the
                        % voltage from the roigroup, but just apply the
                        % last written value instead
                        obj.hCtl.resonantScannerActivate(true,obj.hCtl.resonantScannerLastWrittenValue);
                    else
                        obj.hCtl.resonantScannerActivate(obj.keepResonantScannerOn);
                    end
                end
            end
        end
        
        function updateLiveValues(obj,regenAO)
            % updateLiveValues updates the scanner output waveforms after
            %       scan parameters have changed
            %
            %   obj.updateLiveValues()          regenerates the output waveforms and updates the output buffer
            %   obj.updateLiveValues(regenAO)   if regenAO == true regenerates the output waveforms, then updates the output buffer
            
            if nargin < 2
                regenAO = true;
            end
            
            obj.hCtl.updateLiveValues(regenAO);
            
            if obj.active && strcmpi(obj.hSI.acqState,'focus')
                obj.hAcq.bufferAcqParams(true);
            end
        end
        
        function updateSliceAO(obj)
            % updateSliceAO updates the scan paramters during a slow-z
            %    stack and refreshes the output waveforms
            %
            %  obj.updateSliceAO()
            
            obj.hCtl.updateLiveValues(false);
        end
    end
    
    %%% Resonant scanning specific methods
    methods
        function calibrateGalvos(obj)
            hWb = waitbar(0,'Calibrating Scanner','CreateCancelBtn',@(src,evt)delete(ancestor(src,'figure')));
            try
                obj.scannerset.calibrateScanner('G',hWb);
                obj.galvoCalibration = []; % dummy set to store calibration
            catch ME
                hWb.delete();
                rethrow(ME);
            end
            hWb.delete();
        end
        
        function resFreq = measureScannerFrequency(obj)
            % measureScannerFrequency activates the resonant scanner with
            %   the currently selected amplitude and measures the resonant
            %   frequency
            %
            %   resFreq = obj.measureScannerFrequency()   returns the measured resonant frequency
            
            if obj.componentExecuteFunction('measureScannerFrequency')
                
                if ~obj.active
                    obj.hTrig.applyTriggerConfig();
                    obj.hCtl.resonantScannerActivate(true);
                    
                    %update parameters
                    period = obj.hAcq.stateMachineLoopRate / obj.mdfData.nominalResScanFreq;
                    obj.hAcq.hFpga.NominalResonantPeriodTicks = round(period);
                    obj.hAcq.hFpga.MaxResonantPeriodTicks = floor(period*1.1);
                    obj.hAcq.hFpga.MinResonantPeriodTicks = floor(period*0.9);
                    
                    v = obj.hCtl.resonantScannerLastWrittenValue;
                    fprintf('Measuring scanner frequency at zoom voltage of %.3fV...\n',v);
                    
                    % assumption: the scanner frequency should be settled after 2 seconds
                    obj.hCtl.resonantScannerWaitSettle(max(2,obj.mdfData.resonantScannerSettleTime));
                    
                    resFreq = obj.hAcq.calibrateResonantScannerFreq();
                    
                    if ~(obj.active || obj.keepResonantScannerOn)
                        obj.hCtl.resonantScannerActivate(false);
                    end
                    
                    if isnan(resFreq)
                        most.idioms.dispError('Failed to read scanner frequency. Period clock pulses not detected.\nVerify zoom control/period clock wiring and MDF settings.\n');
                    else
                        fprintf('Scanner Frequency calibrated: %.2fHz\n',resFreq);
                        obj.scanFreqMap(round(v*1000)/1000) = resFreq;
                        
                        if ~obj.active
                            %Side-effects
                            obj.scannerFrequency = resFreq;
                            obj.hAcq.computeMask();
                            obj.saveMaps(false,true);
                        end
                    end
                    
                elseif obj.enableContinuousFreqMeasurement
                    
                    if isempty(obj.lastLiveScannerFreqMeasTime)
                        fprintf('Continuous measurement is enabled but no reading has been made yet.\n');
                    else
                        v = obj.hCtl.resonantScannerLastWrittenValue;
                        resFreq = obj.liveScannerFreq;
                        
                        fprintf('Continuous measurement is enabled. Last sample was taken %.2f seconds ago for zoom voltage of %.3fV: %.2fHz\n',etime(clock,obj.lastLiveScannerFreqMeasTime),v,resFreq);
                        
                        obj.scanFreqMap(round(v*1000)/1000) = resFreq;
                    end
                end
            end
        end
        
        function measureScannerFrequencySweep(obj,measPoints)
            % measureScannerFrequency activates the resonant scanner and measures resonant frequency at
            %    each amplitude in measPoints; the calibration data is stored in the object
            %
            %    obj.measureScannerFrequencySweep(measPoints)   calibrates the resonant frequency for measPoints - a 1xN numeric
            %                 array with voltage amplitudes of the resonant scanner
            
            if obj.componentExecuteFunction('measureScannerFrequencySweep')
                N = numel(measPoints);
                if N > 1
                    fprintf('Measuring scanner frequency at %d points. Press ctrl+c to cancel at any time.\n', N);
                end
                
                measPoints = round(measPoints*1000)/1000;
                
                onCleanup(@()cancelFunc);
                messy = false;
                
                for i = 1:N
                    messy = true;
                    fprintf('Measuring scanner frequency at amplitude of %.3fV (point %d of %d)... ', measPoints(i), i, N);
                    
                    obj.hCtl.resonantScannerActivate(true,measPoints(i));
                    obj.hCtl.resonantScannerWaitSettle(2);
                    resFreq = obj.hAcq.calibrateResonantScannerFreq();
                    obj.hCtl.resonantScannerActivate(false);
                    
                    if isnan(resFreq)
                        most.idioms.dispError('\nFailed to read scanner frequency. Period clock pulses not detected.\nVerify zoom control/period clock wiring and MDF settings.\n');
                        messy = false;
                        return;
                    else
                        fprintf('Done. Result: %.2fHz\n', resFreq);
                        messy = false;

                        obj.scanFreqMap(measPoints(i)) = resFreq;
                        obj.saveMaps(false, true);
                    end
                end
            end
            
            function cancelFunc
                if messy
                    obj.hCtl.resonantScannerActivate(false);
                    fprintf('Cancelled.\n');
                end
            end
        end
        
        function createResFov2VoltsCalPoint(obj, fov, interpRange)
            % if interp range is non zero, two additional control points are created at the specified distance from the main point
            % to limit the range of effect on the interpolated curve
            if nargin < 2 || isempty(fov)
                fov = obj.hCtl.nextResonantFov;
            end
            
            fov = round(fov*100000)/100000;
            obj.resFov2VoltsMap(fov) = obj.zzzResonantFov2Volts(fov);
            
            if nargin > 2 && ~isempty(interpRange) && interpRange > 0
                fovh = round((fov + interpRange)*100000)/100000;
                if fovh < obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree
                    obj.resFov2VoltsMap(fovh) = obj.zzzResonantFov2Volts(fovh);
                end
                fovl = round((fov - interpRange)*100000)/100000;
                if fovl > 0
                    obj.resFov2VoltsMap(fovl) = obj.zzzResonantFov2Volts(fovl);
                end
            end
        end
        
        function setResFov2VoltsCalPoint(obj, fov, v)
            maxV = obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree;
            v = max(0,min(v,maxV));
            fov = round(fov*100000)/100000;
            obj.resFov2VoltsMap(fov) = v;
            obj.updateLiveValues();
        end
        
        function removeResFov2VoltsCalPoint(obj, fov)
            % if interp range is non zero, two additional control points are create at the specified distance from the main point
            % to limit the range of effect on the interpolated curve
            if nargin < 2 || isempty(fov)
                fov = obj.hCtl.nextResonantFov;
            end

            fov = round(fov*100000)/100000;
            if obj.resFov2VoltsMap.isKey(fov)
                obj.resFov2VoltsMap.remove(fov);
            end
            obj.updateLiveValues();
        end
        
        function clearResFov2VoltsCal(obj)
            obj.resFov2VoltsMap = containers.Map([1 0],[obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree 0]);
            obj.updateLiveValues();
        end
        
        function fov2VoltageCal = exportFov2VoltageCal(obj,filename)
            % exportFov2VoltageCal exports the calibration curve used for correcting the resonant scanner
            %   amplitude at different zoom levels
            %
            %   fov2VoltageCal = obj.exportFov2VoltageCal()  returns the calibration info
            %   obj.exportFov2VoltageCal()  opens a file dialog, then exports the calibration info to the selected path
            %   obj.exportFov2VoltageCal(filename)  exports the calibration info to the path specified in 'filename'
            
            if nargin < 2
                filename = '';
            end
            
            if nargout == 0 && isempty(filename)
                [name,path] = uigetfile('.mat','Choose file to save resonant voltage cal','fov2VoltageCal.mat');
                if name==0;return;end
                filename = fullfile(path,file);
            end
            
            fov2VoltageCal.angularRange = obj.mdfData.resonantAngularRange;
            fov2VoltageCal.voltsPerOpticalDegree = obj.mdfData.rScanVoltsPerOpticalDegree;
            fov2VoltageCal.fov = cell2mat(obj.resFov2VoltsMap.keys);
            fov2VoltageCal.angle = fov2VoltageCal.fov * obj.mdfData.resonantAngularRange;
            fov2VoltageCal.volts = cell2mat(obj.resFov2VoltsMap.values);
            
            if ~isempty(filename)
                save(filename,'fov2VoltageCal','-mat');
            end
        end
        
        function importFov2VoltageCal(obj,calOrFile)
            % importFov2VoltageCal imports the calibration curve used for correcting the resonant scanner
            %   amplitude at different zoom levels from a file
            %
            %   obj.importFov2VoltageCal(calOrFile) imports the calibration info either from a structure or the filepath specified in 'calOrFile'
            
            if nargin < 2 || isempty(calOrFile)
                [filename,pathname] = uigetfile('.mat','Choose file to load resonant voltage cal','fov2VoltageCal.mat');
                if filename==0;return;end
                calOrFile = fullfile(pathname,filename);
            end
            
            if ischar(calOrFile)
                fov2VoltageCal = load(filename,'-mat','fov2VoltageCal');
            elseif isstruct(calOrFile) && all(isfield(calOrFile, {'angularRange','voltsPerOpticalDegree','fov','volts'}))
                fov2VoltageCal = calOrFile;
            else
                error('Unkown input format.');
            end
            
            assignin('base','fov2VoltageCalBak',obj.exportFov2VoltageCal);
            
            % scale if zoom level 1 is at a different voltage
            fov2VoltageCal.fov = fov2VoltageCal.fov * (fov2VoltageCal.angularRange * fov2VoltageCal.voltsPerOpticalDegree)/(obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree);
            
            inds = fov2VoltageCal.fov(fov2VoltageCal.fov > 1);
            fov2VoltageCal.fov(inds) = [];
            fov2VoltageCal.volts(inds) = [];
            
            obj.resFov2VoltsMap = containers.Map(fov2VoltageCal.fov,fov2VoltageCal.volts);
        end
        
        function clearZoomToLinePhaseCal(obj)
            % clearZoomToLinePhaseCal clears the look up table that stores
            %    the line phase for different zoom factors
            %
            %   obj.clearZoomToLinePhaseCal()
            
            obj.linePhaseMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
        end
        
        function clearZoomToScanFreqCal(obj)
            % clearZoomToScanFreqCal clears the look up table that stores
            %    the resonant scanner frequency for different zoom factors
            %
            %   obj.clearZoomToLinePhaseCal()
            
            obj.scanFreqMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
        end
    end
    
    %% FRIEND METHODS
    methods (Hidden)
        function ss = getScannerset(obj, enableResonant, forStim)
            % Determine flyback time per frame
            if enableResonant
                flybackTimeDiv = obj.scannerFrequency;
                
                % Define Resonant Scanning Hardware.
                r = scanimage.mroi.scanners.Resonant(obj.mdfData.resonantAngularRange,...
                    @obj.zzzResonantFov2Volts,...
                    obj.bidirectional,...
                    1/obj.scannerFrequency,...
                    obj.fillFractionSpatial,...
                    obj.sampleRateCtl);
            else
                flybackTimeDiv = obj.sampleRateCtl;
            end
            
            if obj.hSI.hStackManager.isFastZ && strcmp(obj.hSI.hFastZ.waveformType, 'step')
                Nsteps = ceil(obj.hSI.hFastZ.flybackTime * flybackTimeDiv);
                flybackTime = max(obj.coercedFlybackTime, Nsteps / flybackTimeDiv);
            else
                flybackTime = obj.coercedFlybackTime;
            end
            
            if forStim
                ctlFs = 1e6;
            else
                ctlFs = obj.sampleRateCtl;
            end
            
            % Define Y-Galvo Scanning Hardware.
            assert(~isempty(obj.yGalvo),'yGalvo is not defined in machine data file');
            obj.yGalvo.travelRange = [-obj.mdfData.yGalvoAngularRange obj.mdfData.yGalvoAngularRange]./2;
            obj.yGalvo.voltsPerDistance = obj.mdfData.galvoVoltsPerOpticalDegreeY;
            obj.yGalvo.flytoTimeSeconds = obj.coercedFlytoTime;
            obj.yGalvo.flybackTimeSeconds = flybackTime;
            obj.yGalvo.sampleRateHz = ctlFs;
            
            % Define X-Galvo Scanning Hardware.
            if ~isempty(obj.xGalvo)
                obj.xGalvo.travelRange = [-obj.mdfData.xGalvoAngularRange obj.mdfData.xGalvoAngularRange]./2;
                obj.xGalvo.voltsPerDistance = obj.mdfData.galvoVoltsPerOpticalDegreeX;
                obj.xGalvo.flytoTimeSeconds = obj.coercedFlytoTime;
                obj.xGalvo.flybackTimeSeconds = flybackTime;
                obj.xGalvo.sampleRateHz = ctlFs;
            end
            
            % Define beam hardware
            if obj.hSI.hBeams.numInstances && ~isempty(obj.beamDaqID)
                beams = obj.hSI.hBeams.scanner(obj.beamDaqID,ctlFs,obj.linePhase,obj.beamClockDelay,obj.beamClockExtend,obj.mdfData.beamIds);
                beams.includeFlybackLines = true;
                if obj.hSI.hRoiManager.isLineScan
                    beams.powerBoxes = [];
                end
            else
                beams = [];
            end
            
            % Define fastz hardware
            fastz = obj.hSI.hFastZ.scanner(obj.name);
            if ~isempty(fastz)
                fastz.sampleRateHz = ctlFs;
            end
            
            if enableResonant
                % Create resonant galvo galvo scannerset using hardware descriptions above
                ss=scanimage.mroi.scannerset.ResonantGalvoGalvo(obj.name,r,obj.xGalvo,obj.yGalvo,beams,fastz,obj.fillFractionSpatial);
                ss.useScannerTimebase = obj.hCtl.useScannerSampleClk;
                ss.extendedRggFov = obj.extendedRggFov;
            else
                % Create galvo galvo scannerset using hardware descriptions above
                stepY = false; % ????????
                ss = scanimage.mroi.scannerset.GalvoGalvo(obj.name,obj.xGalvo,obj.yGalvo,beams,fastz,...
                    obj.fillFractionSpatial,obj.pixelBinFactor/obj.sampleRate,obj.bidirectional,stepY,0);
                ss.acqSampleRate = obj.sampleRate;
            end
            
            ss.hCSSampleRelative = obj.hSI.hMotors.hCSSampleRelative;
            ss.hCSReference = obj.hSI.hCoordinateSystems.hCSReference;
        end
    end
    
    %% INTERNAL METHODS
    methods (Hidden)
        function reinitRoutes(obj)
            obj.hTrig.reinitRoutes();
        end
        
        function deinitRoutes(obj)
            if (~obj.simulated)
                obj.hAcq.hAcqFifo.close();
                obj.hAcq.hAuxFifo.close();
            end
            obj.hTrig.deinitRoutes();
        end
        
        function frameAcquiredFcn(obj)
            if obj.active
                if obj.enableBenchmark
                    t = tic();
                end
                
                obj.stripeAcquiredCallback(obj,[]);
                
                if obj.enableBenchmark
                    T = toc(t);
                    obj.lastFrameAcqFcnTime = T;
                    obj.totalFrameAcqFcnTime = obj.totalFrameAcqFcnTime + T;
                    
                    benchmarkData = obj.hAcq.benchmarkData;
                    framesProcessed = obj.hAcq.framesProcessed;
                    
                    fcut = benchmarkData.frameCopierProcessTime/10e3;
                    fcutpf = fcut/benchmarkData.totalAcquiredFrames;
                    fccpucpf = benchmarkData.frameCopierCpuCycles/benchmarkData.totalAcquiredFrames;
                    
                    flut = benchmarkData.frameLoggerProcessTime/10e3;
                    flutpf = flut/benchmarkData.totalAcquiredFrames;
                    flcpucpf = benchmarkData.frameLoggerCpuCycles/benchmarkData.totalAcquiredFrames;
                    
                    faft = obj.totalFrameAcqFcnTime*1000/framesProcessed;
                    drops = benchmarkData.totalAcquiredFrames - framesProcessed;
                    pctDrop = drops * 100 / benchmarkData.totalAcquiredFrames;
                    
                    td = tic;
                    drawnow('nocallbacks');
                    td = toc(td);
                    
                    obj.totalDispUpdates = obj.totalDispUpdates + 1;
                    obj.totalDispUpdateTime = obj.totalDispUpdateTime + td;
                    
                    aveDispTime = obj.totalDispUpdateTime*1000/obj.totalDispUpdates;
                    nskipped = benchmarkData.totalAcquiredFrames-obj.totalDispUpdates;
                    pctSkipped = nskipped * 100 / benchmarkData.totalAcquiredFrames;
                    
                    fps = obj.totalDispUpdates/etime(clock,obj.hSI.acqStartTime);
                    
                    fprintf('Frm copier: %.3fms/fr, %.3f cpu clks/frm, %.3f cpu ms/frm.   Frm logger: %.3fms/fr, %.3f cpu clks/frm, %.3f cpu ms/frm.   MATLAB: %.3fms/fr, %d (%.2f%%) dropped.   Display Update: %.1fms/fr, %d (%.2f%%) skipped, %.2ffps\n',...
                        fcutpf,fccpucpf,fccpucpf*1000/obj.cpuFreq,flutpf,flcpucpf,flcpucpf*1000/obj.cpuFreq,faft,drops,pctDrop,aveDispTime,nskipped,pctSkipped,fps);
                end
            end
        end
        
        function val = zzzEstimateLinePhase(obj,resonantOutputVolts)
            %Restrict resolution of map
            resonantOutputVolts = round(resonantOutputVolts*1000)/1000;
            
            if isempty(resonantOutputVolts) || isempty(keys(obj.linePhaseMap))
                %If there are no keys in the phase map or no voltage param set, default to zero.
                val = 0;
            else
                linePhaseMapArray = cell2mat(keys(obj.linePhaseMap));
                
                if ismember(resonantOutputVolts, linePhaseMapArray)
                    %If the resonant voltage is a key in the linePhaseMap, simply return its value.
                    val = obj.linePhaseMap(resonantOutputVolts);
                else
                    %If the resonant voltage is not a key in the linePhaseMap, then
                    %interpolate (or extrapolate) value from its nearest neighbors.
                    %Find the first key below this resonant voltage level.
                    lowKey = linePhaseMapArray(find(resonantOutputVolts>linePhaseMapArray,1,'last'));
                    %Find the first key above this resonant voltage level.
                    highKey = linePhaseMapArray(find(resonantOutputVolts<linePhaseMapArray,1,'first'));
                    if isempty(lowKey)
                        %If there is no key with a lower resonant voltage than
                        %the current one, return the val corresponding to the
                        %next lower known resonant voltage.
                        val = obj.linePhaseMap(highKey);
                    elseif isempty(highKey)
                        %If there is no key with a higher resonant voltage than
                        %the current one, return the val corresponding to the
                        %next higher known resonant voltage.
                        val = obj.linePhaseMap(lowKey);
                    else
                        %The usual case: There is a defined phase for resonant
                        %voltages greater than and less than he current one.
                        switch obj.linePhaseMode
                            % High and low are swapped because zoom is inverse to voltage
                            case 'Next Lower'
                                val = obj.linePhaseMap(highKey);
                            case 'Next Higher'
                                val = obj.linePhaseMap(lowKey);
                            case 'Nearest Neighbor'
                                if (highKey - resonantOutputVolts) > (resonantOutputVolts - lowKey)
                                    val = obj.linePhaseMap(lowKey);
                                else
                                    val = obj.linePhaseMap(highKey);
                                end
                            case 'Interpolate'
                                uniqueKeyVals = unique(linspace(lowKey,highKey));
                                
                                val = interp1(uniqueKeyVals, ...
                                    linspace(obj.linePhaseMap(lowKey), ...
                                    obj.linePhaseMap(highKey),numel(uniqueKeyVals)),resonantOutputVolts);
                        end
                    end
                end
            end
        end
        
        function val = zzzEstimateScanFreq(obj,resonantOutputVolts)
            %Restrict resolution of map
            resonantOutputVolts = round(resonantOutputVolts*1000)/1000;
            
            if isempty(resonantOutputVolts) || resonantOutputVolts == 0
                val = obj.mdfData.nominalResScanFreq;
            elseif isempty(keys(obj.scanFreqMap))
                val = obj.measureScannerFrequency();
            else
                scanFreqMapArray = cell2mat(keys(obj.scanFreqMap));
                
                if ismember(resonantOutputVolts, scanFreqMapArray)
                    %If the resonant voltage is a key in the scanFreqMap, simply return its value.
                    val = obj.scanFreqMap(resonantOutputVolts);
                else
                    val = obj.measureScannerFrequency();
                end
            end
            
            if isnan(val)
                val = obj.mdfData.nominalResScanFreq;
            end
        end
        
        function val = zzzResonantFov2Volts(obj,fov)
            %Restrict resolution of map
            fov = round(fov*100000)/100000;
            assert((fov <= 1) && (fov >= 0), 'FOV out of range.');
            
            if obj.useNonlinearResonantFov2VoltsCurve
                if isempty(keys(obj.resFov2VoltsMap))
                    %If there are no keys in the phase map, return default
                    val = obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree * fov;
                else
                    resFov2VoltsMapArray = cell2mat(keys(obj.resFov2VoltsMap));
                    
                    if ismember(fov, resFov2VoltsMapArray)
                        %If the fov is a key in the resFov2VoltsMap, simply return its value.
                        val = obj.resFov2VoltsMap(fov);
                    else
                        %If the resonant fov is not a key in the resFov2VoltsMap, then
                        %interpolate (or extrapolate) value from its nearest neighbors.
                        
                        %Find the first key below this resonant voltage level.
                        lowKey = resFov2VoltsMapArray(find(fov>resFov2VoltsMapArray,1,'last'));
                        if isempty(lowKey)
                            lowKey = 0;
                            lowVal = 0;
                        else
                            lowVal = obj.resFov2VoltsMap(lowKey);
                        end
                        
                        %Find the first key above this resonant voltage level.
                        highKey = resFov2VoltsMapArray(find(fov<resFov2VoltsMapArray,1,'first'));
                        if isempty(highKey)
                            highKey = 1;
                            highVal = obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree;
                        else
                            highVal = obj.resFov2VoltsMap(highKey);
                        end
                        
                        val = interp1([lowKey highKey], [lowVal highVal], fov);
                    end
                end
            else
                val = obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree * fov;
            end
        end
        
        function loadClassData(obj)
            ks = obj.getClassDataVar('linePhaseMap_ks',obj.classDataFileName);
            vs = obj.getClassDataVar('linePhaseMap_vs',obj.classDataFileName);
            if ~isa(ks,'double') || ~isa(vs,'double') || numel(ks) ~= numel(vs)
                most.idioms.warn('Line phase map from Class Data File contained unexpected data. Replacing with empty map.');
                obj.linePhaseMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
            elseif isempty(ks)
                obj.linePhaseMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
            else
                obj.linePhaseMap = containers.Map(ks,vs);
            end
            
            scanFreqNominal_ = obj.getClassDataVar('scanFreqNominal',obj.classDataFileName);
            if isempty(scanFreqNominal_) || scanFreqNominal_ == obj.mdfData.nominalResScanFreq
                ks = obj.getClassDataVar('scanFreqMap_ks',obj.classDataFileName);
                vs = obj.getClassDataVar('scanFreqMap_vs',obj.classDataFileName);
            else
                most.idioms.warn('Detected changed nominal resonant frequency. Resetting resonant frequency map.');
                ks = double([]);
                vs = double([]);
            end
            
            if ~isa(ks,'double') || ~isa(vs,'double') || numel(ks) ~= numel(vs)
                most.idioms.warn('Scan freq map from Class Data File contained unexpected data. Replacing with empty map.');
                obj.scanFreqMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
            elseif isempty(ks)
                obj.scanFreqMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
            else
                obj.scanFreqMap = containers.Map(ks,vs);
            end
            
            if obj.hasResonantMirror
                ks = obj.getClassDataVar('resFov2VoltsMap_ks',obj.classDataFileName);
                vs = obj.getClassDataVar('resFov2VoltsMap_vs',obj.classDataFileName);
                if ~isa(ks,'double') || ~isa(vs,'double') || numel(ks) ~= numel(vs)
                    most.idioms.warn('Resonant voltage map from Class Data File contained unexpected data. Replacing with default map.');
                    obj.resFov2VoltsMap = containers.Map([1 0],[obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree 0]);
                elseif isempty(ks)
                    obj.resFov2VoltsMap = containers.Map([1 0],[obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree 0]);
                else
                    nmax = obj.getClassDataVar('resFov2VoltsMap_nom_max',obj.classDataFileName);
                    if obj.useNonlinearResonantFov2VoltsCurve && ~isempty(nmax) && abs(nmax - obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree) > 0.001
                        most.idioms.warn('The resonant scanner voltage settings have changed. The resonant calibration map must be reset for the change to take effect.');
                    end
                    obj.resFov2VoltsMap = containers.Map(ks,vs);
                end
                
                obj.useNonlinearResonantFov2VoltsCurve_ = obj.getClassDataVar('useNonlinearResonantFov2VoltsCurve',obj.classDataFileName);
                obj.keepResonantScannerOn = obj.getClassDataVar('keepResonantScannerOn',obj.classDataFileName);
                obj.linePhaseMode = obj.getClassDataVar('linePhaseMode',obj.classDataFileName);
            end
            
            galvoCalibration_ = obj.getClassDataVar('galvoCalibration',obj.classDataFileName);
            if isstruct(galvoCalibration_) && isfield(galvoCalibration_,'xGalvo') && ~isempty(obj.xGalvo)
                obj.xGalvo.calibrationData = galvoCalibration_.xGalvo;
            end
            
            if isstruct(galvoCalibration_) && isfield(galvoCalibration_,'yGalvo') && ~isempty(obj.yGalvo)
                obj.yGalvo.calibrationData = galvoCalibration_.yGalvo;
            end
        end
        
        
        function saveMaps(obj,savePhaseMap,saveFreqMap,saveVoltageMap)
            
            if ~obj.numInstances
                % init did not complete successfuly
                return;
            end
            
            if nargin < 2
                savePhaseMap = true;
            end
            
            if nargin < 3
                saveFreqMap = true;
            end
            
            if nargin < 4
                saveVoltageMap = true;
            end
            
            if savePhaseMap && most.idioms.isValidObj(obj.linePhaseMap) && obj.hasResonantMirror
                obj.setClassDataVar('linePhaseMap_ks',cell2mat(obj.linePhaseMap.keys),obj.classDataFileName);
                obj.setClassDataVar('linePhaseMap_vs',cell2mat(obj.linePhaseMap.values),obj.classDataFileName);
            end
            
            if saveFreqMap && obj.hasResonantMirror
                obj.setClassDataVar('scanFreqNominal',obj.mdfData.nominalResScanFreq,obj.classDataFileName);
                obj.setClassDataVar('scanFreqMap_ks',cell2mat(obj.scanFreqMap.keys),obj.classDataFileName);
                obj.setClassDataVar('scanFreqMap_vs',cell2mat(obj.scanFreqMap.values),obj.classDataFileName);
            end
            
            if saveVoltageMap && obj.hasResonantMirror
                obj.setClassDataVar('resFov2VoltsMap_ks',cell2mat(obj.resFov2VoltsMap.keys),obj.classDataFileName);
                obj.setClassDataVar('resFov2VoltsMap_vs',cell2mat(obj.resFov2VoltsMap.values),obj.classDataFileName);
                nmax = obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree;
                obj.setClassDataVar('resFov2VoltsMap_nom_max',nmax,obj.classDataFileName);
            end
        end
        
        function zprvEnsureClassDataFileProps(obj)
            obj.ensureClassDataFile(struct('galvoCalibration',struct()),obj.classDataFileName);
            
            obj.ensureClassDataFile(struct('linePhaseMap_ks',double([])),obj.classDataFileName);
            obj.ensureClassDataFile(struct('linePhaseMap_vs',double([])),obj.classDataFileName);
            
            obj.ensureClassDataFile(struct('scanFreqNominal',double([])),obj.classDataFileName);
            obj.ensureClassDataFile(struct('scanFreqMap_ks',double([])),obj.classDataFileName);
            obj.ensureClassDataFile(struct('scanFreqMap_vs',double([])),obj.classDataFileName);
            
            obj.ensureClassDataFile(struct('resFov2VoltsMap_ks',double([])),obj.classDataFileName);
            obj.ensureClassDataFile(struct('resFov2VoltsMap_vs',double([])),obj.classDataFileName);
            nmax = obj.mdfData.resonantAngularRange * obj.mdfData.rScanVoltsPerOpticalDegree;
            obj.ensureClassDataFile(struct('resFov2VoltsMap_nom_max',nmax),obj.classDataFileName);
            
            obj.ensureClassDataFile(struct('useNonlinearResonantFov2VoltsCurve',false),obj.classDataFileName);
            obj.ensureClassDataFile(struct('keepResonantScannerOn',false),obj.classDataFileName);
            obj.ensureClassDataFile(struct('linePhaseMode','Nearest Neighbor'),obj.classDataFileName);
        end
        
        function applyScanModeCachedProps(obj)
            if isfield(obj.scanModePropCache, obj.scanMode)
                s = obj.scanModePropCache.(obj.scanMode);
                propNames = fieldnames(s);
                for i = 1:numel(propNames)
                    propName = propNames{i};
                    obj.(propName) = s.(propName);
                end
            end
            
            if obj.scanModeIsResonant
                v = obj.hCtl.nextResonantVoltage;
                obj.flagZoomChanged = true;
                obj.linePhase = obj.zzzEstimateLinePhase(v);
            end
        end
    end
    
    %%% Abstract methods realizations (scanimage.interfaces.Scan2D)    
    methods (Hidden)
        function arm(obj)
            if obj.scanModeIsResonant
                resAmplitude = obj.hCtl.nextResonantVoltage;
                
                if resAmplitude > 0.0001
                    obj.hCtl.resonantScannerActivate(true, resAmplitude);
                    newFreq = obj.zzzEstimateScanFreq(resAmplitude);
                    
                    % avoid pointless change
                    if (abs(newFreq - obj.scannerFrequency) / obj.scannerFrequency) > 0.00001
                        obj.scannerFrequency = newFreq;
                    end
                end
            elseif obj.hasResonantMirror
                obj.hCtl.resonantScannerActivate(false);
                
                if ~obj.hSI.hRoiManager.isLineScan 
                    assert(obj.ctlRateGood, 'Could not find a scanner control rate fitting the desired scan parameters. Try adjusting the acq sample rate or ROI pixel counts.');
                end
            end
            
            obj.hAcq.bufferAcqParams();
        end
        
        function data = acquireSamples(obj,numSamples)
            if obj.componentExecuteFunction('acquireSamples',numSamples)
                data = zeros(numSamples,obj.channelsAvailable,obj.channelsDataType); % preallocate data
                for i = 1:numSamples
                    data(i,:) = obj.hAcq.rawAdcOutput(1,1:obj.channelsAvailable);
                end
            end
        end
        
        function zzFeedbackDataAcquiredCallback(obj, data, numFrames, nSamples, lastFrameStartIdx)
            if numFrames
                obj.lastFramePositionData = data(lastFrameStartIdx:end,:);
            else
                obj.lastFramePositionData(lastFrameStartIdx:lastFrameStartIdx+nSamples-1,:) = data;
            end
            obj.hSI.hDisplay.updatePosFdbk();
        end
        
        function signalReadyReceiveData(obj)
            if ~obj.scanModeIsLinear
                obj.hAcq.signalReadyReceiveData();
            end
        end
                
        function [success,stripeData] = readStripeData(obj)
            % remove the componentExecute protection for performance
            %if obj.componentExecuteFunction('readStripeData')
                [success,stripeData] = obj.hAcq.readStripeData();
                if ~isempty(stripeData) && stripeData.endOfAcquisitionMode
                    obj.abort(); %self abort if acquisition is done
                end
            %end
        end
        
        function newPhase = calibrateLinePhase(obj)
            if obj.scanModeIsLinear
                roiDatas = obj.hSI.hDisplay.lastStripeData.roiData;
                if ~isempty(roiDatas)
                    for ir = numel(roiDatas):-1:1
                        im = vertcat(roiDatas{ir}.imageData{:});
                        
                        if roiDatas{ir}.transposed
                            im = cellfun(@(imt){imt'},im);
                        end
                        
                        imData{ir,1} = vertcat(im{:});
                    end
                    
                    if numel(unique(cellfun(@(d)size(d,2),imData)))
                        imData = imData{1};
                    else
                        imData = vertcat(imData{:});
                    end
                    
                    if ~isempty(imData)
                        [im1,im2] = deinterlaceImage(imData);
                        [~,pixelPhase] = detectPixelOffset(im1,im2);
                        samplePhase = obj.pixelBinFactor * pixelPhase;
                        phaseOffset = samplePhase / obj.sampleRate;
                        obj.linePhase = obj.linePhase - phaseOffset / 2;
                    end
                end
            else
                im = getImage();
                
                ff_s = obj.fillFractionSpatial;
                ff_t = obj.fillFractionTemporal;
                
                if ~obj.uniformSampling
                    im = imToTimeDomain(im,ff_s,ff_t);
                end
                
                im_odd  = im(:,1:2:end);
                im_even = im(:,2:2:end);
                
                % first brute force search to find minimum
                offsets_rad = linspace(-1,1,31)*pi/8;
                ds = arrayfun(@(offset_rad)imDifference(im_odd,im_even,ff_s,ff_t,offset_rad),offsets_rad);
                [d,idx] = min(ds);
                offset_rad = offsets_rad(idx);
                
                % secondary brute force search to refine minimum
                offsets_rad = offset_rad+linspace(-1,1,51)*diff(offsets_rad(1:2));
                ds = arrayfun(@(offset_rad)imDifference(im_odd,im_even,ff_s,ff_t,offset_rad),offsets_rad);
                [d,idx] = min(ds);
                offset_rad = offsets_rad(idx);
                
                offsetLinePhase = offset_rad /(2*pi)/obj.scannerFrequency;
                obj.linePhase =  obj.linePhase - offsetLinePhase;
            end
            
            newPhase = obj.linePhase;
            
            %%% Local Functions
            function [d,im] = imDifference(im_odd, im_even, ff_s, ff_t, offset_rad)                
                im_odd  = imToSpatialDomain(im_odd , ff_s, ff_t, offset_rad);
                im_even = imToSpatialDomain(im_even, ff_s, ff_t,-offset_rad);
                
                d = im_odd - im_even;
                d(isnan(d)) = []; % remove artifacts from interpolation
                d = sum(abs(d(:))) ./ numel(d); % least square difference, normalize by number of elements
                
                if nargout > 1
                    im = cat(3,im_odd,im_even);
                    im = permute(im,[1,3,2]);
                    im = reshape(im,size(im,1),[]);
                end
            end
            
            function im = imToTimeDomain(im,ff_s,ff_t)
                nPix = size(im,1);
                xx_lin = linspace(-ff_s,ff_s,nPix);
                xx_rad = linspace(-ff_t,ff_t,nPix)*pi/2;
                xx_linq = sin(xx_rad);
                
                im = interp1(xx_lin,im,xx_linq,'linear',NaN);
            end
            
            function im = imToSpatialDomain(im,ff_s,ff_t,offset_rad)
                nPix = size(im,1);
                xx_rad = linspace(-ff_t,ff_t,nPix)*pi/2+offset_rad;
                xx_lin = linspace(-ff_s,ff_s,nPix);
                xx_radq = asin(xx_lin);
                
                im = interp1(xx_rad,im,xx_radq,'linear',NaN);
            end
            
            function im = getImage()
                %get image from every roi
                roiDatas = obj.hSI.hDisplay.lastStripeData.roiData;
                for i = numel(roiDatas):-1:1
                    im = vertcat(roiDatas{i}.imageData{:});
                    
                    if ~roiDatas{i}.transposed
                        im = cellfun(@(imt){imt'},im);
                    end
                    
                    imData{i,1} = horzcat(im{:});
                end
                im = horzcat(imData{:});
                
                nLines = size(im,2);
                if nLines > 1024
                    im(:,1025:end) = []; % this should be enough lines for processing
                elseif mod(nLines,2)
                    im(:,end) = []; % crop to even number of lines
                end
                
                im = single(im);
            end
            
            function [im1, im2] = deinterlaceImage(im)
                im1 = im(1:2:end,:);
                im2 = im(2:2:end,:);
            end
            
            function [iOffset,jOffset] = detectPixelOffset(im1,im2)
                numLines = min(size(im1,1),size(im2,1));
                im1 = im1(1:numLines,:);
                im2 = im2(1:numLines,:);

                c = real(most.mimics.xcorr2circ(single(im1),single(im2)));
                cdim = size(c);
                [~,idx] = max(c(:));
                [i,j] = ind2sub(cdim,idx);
                iOffset = floor((cdim(1)/2))+1-i;
                jOffset = floor((cdim(2)/2))+1-j;
            end
        end
        
        function reloadMdf(obj,varargin)
            obj.reloadMdf@scanimage.interfaces.Component(varargin{:})
            obj.hTrig.laserTriggerIn = obj.mdfData.LaserTriggerPort;
        end
    end
    
    %%% Abstract methods realizations (scanimage.interfaces.Component)
    methods (Access = protected, Hidden)
        function mdlInitialize(obj)
            obj.scanModePropCache = defaultModeProps();
            
            if ~obj.hasResonantMirror
                % class props all default to settings for resonant
                % scanning. if this is a GG only system, swtich to
                % the linear scanning prop set
                obj.applyScanModeCachedProps();
            end
            
            mdlInitialize@scanimage.components.Scan2D(obj);
            obj.hPixListener = most.ErrorHandler.addCatchingListener(obj.hSI.hRoiManager, 'pixPerLineChanged',@updateCtlSampRate);
            
            function updateCtlSampRate(varargin)
                if obj.hSI.hScan2D == obj
                    obj.sampleRateCtl = [];
                end
            end
            
            function s = defaultModeProps()
                lsr = 2e6 + 5e5*obj.hAcq.hFpga.isR1;
                s.linear = struct('sampleRate', lsr, 'pixelBinFactor', 8, 'fillFractionSpatial', .9, 'bidirectional', true, 'stripingEnable', true, 'linePhase', 0);
                s.resonant = struct('uniformSampling', false, 'pixelBinFactor', 1, 'fillFractionSpatial', .9, 'bidirectional', true, 'stripingEnable', false, 'linePhase', 0);
            end
        end

        function componentStart(obj)
            assert(~obj.robotMode);
            obj.independentComponent = false;
            obj.totalFrameAcqFcnTime = 0;
            obj.totalDispUpdates = 0;
            obj.totalDispUpdateTime = 0;
            
            obj.hTrig.start();
            obj.hCtl.start();
            obj.hAcq.start();
            
            obj.flagZoomChanged = false;
            obj.linePhase_ = [];
        end
        
        function componentAbort(obj,soft)
            if nargin < 2 || isempty(soft)
                soft = false;
            end
            
            obj.hAcq.abort();
            obj.hCtl.stop(soft);
            obj.hTrig.stop();
            
            obj.saveMaps();
            
            obj.flagZoomChanged = false;
            obj.linePhase_ = [];
            obj.independentComponent = true;
        end
        
        
        function fillFracTemp = fillFracSpatToTemp(obj,fillFracSpat)
            if obj.scanModeIsResonant
                fillFracTemp = 2/pi * asin(fillFracSpat);
            else
                fillFracTemp = fillFracSpat;
            end
        end
        
        function fillFracSpat = fillFracTempToSpat(obj,fillFracTemp)
            if obj.scanModeIsResonant
                fillFracSpat = cos( (1-fillFracTemp) * pi/2 );
            else
                fillFracSpat = fillFracTemp;
            end
        end
    end          
    
    %% FRIEND EVENTS
    events (Hidden)
        resonantScannerOutputVoltsUpdated;
    end
    
end

function s = zlclAppendDependsOnPropAttributes(s)
    s.useNonlinearResonantFov2VoltsCurve = struct('Classes','binaryflex');
end

function s = defaultMdfSection()
    s = [...
        makeEntry('simulated',false,'This scanner is simulated')...
        makeEntry('scanheadModel','')...
        makeEntry()... % blank line
        makeEntry('nominalResScanFreq',7910,'[Hz] nominal frequency of the resonant scanner')...
        makeEntry('beamIds',[],'Numeric: IDs of the beams to use with the resonant scan system')...
        makeEntry('shutterIDs',1,'Array of the shutter IDs that must be opened for resonant scan system to operate')...
        makeEntry()... % blank line
        makeEntry('acquisitionDeviceId','vDAQ0','RDI Device ID')...
        makeEntry('acquisitionEngineIdx',1)...
        makeEntry('passiveInit',0)...
        makeEntry('channelsInvert',false,'Logical: Specifies if the input signal is inverted (i.e., more negative for increased light signal)')...
        makeEntry()... % blank line
        makeEntry('externalSampleClock',false,'Logical: use external sample clock connected to the CLK IN terminal of the vDAQ')...
        makeEntry('externalSampleClockRate',[],'[Hz]: nominal frequency of the external sample clock connected to the CLK IN terminal (e.g. 80e6); actual rate is measured on FPGA')...
        makeEntry('externalSampleClockMultiplier',[],'Multiplier to apply to external sample clock')...
        makeEntry()... % blank line
        makeEntry('Galvo mirror settings')... % comment only
        makeEntry('galvoDeviceName','PXI1Slot3','String identifying the NI-DAQ board to be used to control the galvo(s). The name of the DAQ-Device can be seen in NI MAX. e.g. ''Dev1'' or ''PXI1Slot3''. This DAQ board needs to be installed in the same PXI chassis as the FPGA board specified in section')...
        makeEntry('galvoAOChanIDX',[],'The numeric ID of the Analog Output channel to be used to control the X Galvo. Can be empty for standard Resonant Galvo scanners.')...
        makeEntry('galvoAOChanIDY',1,'The numeric ID of the Analog Output channel to be used to control the Y Galvo.')...
        makeEntry()... % blank line
        makeEntry('galvoAIChanIDX',[],'The numeric ID of the Analog Input channel for the X Galvo feedback signal.')...
        makeEntry('galvoAIChanIDY',[],'The numeric ID of the Analog Input channel for the Y Galvo feedback signal.')...
        makeEntry()... % blank line
        makeEntry('xGalvoAngularRange',15,'max range in optical degrees (pk-pk) for x galvo if present')...
        makeEntry('yGalvoAngularRange',15,'max range in optical degrees (pk-pk) for y galvo')...
        makeEntry()... % blank line
        makeEntry('xGalvoSlewRateLimit',100000,'Maximum speed for X Galvo [V/s]. Default is 20 V (full range) in 200 us.')...
        makeEntry('yGalvoSlewRateLimit',100000,'Maximum speed for X Galvo [V/s]. Default is 20 V (full range) in 200 us.')...
        makeEntry('extendedRggFov',false,'If true and x galvo is present, addressable FOV is combination of resonant FOV and x galvo FOV.')...
        makeEntry()... % blank line
        makeEntry('galvoVoltsPerOpticalDegreeX',1.0,'galvo conversion factor from optical degrees to volts (negative values invert scan direction)')...
        makeEntry('galvoVoltsPerOpticalDegreeY',1.0,'galvo conversion factor from optical degrees to volts (negative values invert scan direction)')...
        makeEntry()... % blank line
        makeEntry('galvoParkDegreesX',-8,'Numeric [deg]: Optical degrees from center position for X galvo to park at when scanning is inactive')...
        makeEntry('galvoParkDegreesY',-8,'Numeric [deg]: Optical degrees from center position for Y galvo to park at when scanning is inactive')...
        makeEntry()... % blank line
        makeEntry('Resonant mirror settings')... % comment only
        makeEntry('resonantZoomDeviceName','','String identifying the vDAQ or NI-DAQ board to host the resonant zoom analog output. Leave empty to use same board as specified in ''galvoDeviceName''')...
        makeEntry('resonantZoomAOChanID',0,'resonantZoomAOChanID: The numeric ID of the Analog Output channel to be used to control the Resonant Scanner Zoom level.')...
        makeEntry('resonantSyncInputTerminal','D1.0','(optional) Digital input for the sync (period clock) signal')...
        makeEntry('resonantEnableTerminal',[],'(optional) Digital output that enables/disables the resonant scanner.')...
        makeEntry()... % blank line
        makeEntry('resonantAngularRange',15,'max range in optical degrees (pk-pk) for resonant')...
        makeEntry('rScanVoltsPerOpticalDegree',0.33333333,'resonant scanner conversion factor from optical degrees to volts')...
        makeEntry()... % blank line
        makeEntry('resonantScannerSettleTime',0.5,'[seconds] time to wait for the resonant scanner to reach its desired frequency after an update of the zoomFactor')...
        makeEntry()... % blank line
        makeEntry('Advanced/Optional')... % comment only
        makeEntry('PeriodClockDebounceTime', 100e-9,'[s] time the period clock has to be stable before a change is registered')...
        makeEntry('TriggerDebounceTime', 500e-9,'[s] time acquisition, stop and next trigger to be stable before a change is registered')...
        makeEntry('reverseLineRead', false,'flips the image in the resonant scan axis')...
        makeEntry('bitfileAppendix', '','apendix to bitfile name. Allows to choose from different bitfiles for the same FPGA/digitizer combination')...
        makeEntry()... % blank line
        makeEntry('Aux Trigger Recording, Photon Counting, and I2C are mutually exclusive')...
        makeEntry()... % blank line
        makeEntry('Aux Trigger Recording')... % comment only
        makeEntry('auxTriggersEnable', true)...
        makeEntry('auxTriggersTimeDebounce', 1e-7,'[s] time after an edge where subsequent edges are ignored')...
        makeEntry('auxTriggerInputs', {{'D1.4' 'D1.5' 'D1.6' 'D1.7'}}, 'Digital input lines to use as aux triggers')...
        makeEntry('auxTriggerLinesInvert', false(4,1), '[logical] 1x4 vector specifying polarity of aux trigger inputs')...
        makeEntry()... % blank line
        makeEntry('Signal Conditioning')... % comment only
        makeEntry('disableMaskDivide', [],'disable averaging of samples into pixels; instead accumulate samples')...
        makeEntry('scaleByPowerOfTwo', 0,'scale count by 2^n before averaging to avoid loss of precision by integer division')...
        makeEntry('photonCountingDebounce', 25e-9,'[s] time the TTL input needs to be stable high before a pulse is registered')...
        makeEntry()... % blank line
        makeEntry('I2C')... % comment only
        makeEntry('i2cEnable', false)...
        makeEntry('i2cSdaPort', 'D0.6')...
        makeEntry('i2cSclPort', 'D0.7')...
        makeEntry('i2cAddress', uint8(0),'[byte] I2C address of the FPGA')...
        makeEntry('i2cDebounce', 100e-9,'[s] time the I2C signal has to be stable high before a change is registered')...
        makeEntry('i2cStoreAsChar', false,'if false, the I2C packet bytes are stored as a uint8 array. if true, the I2C packet bytes are stored as a string. Note: a Null byte in the packet terminates the string')...
        makeEntry('i2cSendAck', true, 'When enabled FPGA confirms each packet with an ACK bit by actively pulling down the SDA line')...
        makeEntry()... % blank line
        makeEntry('Laser Trigger')... % comment only
        makeEntry('LaserTriggerPort', '','Digital input where laser trigger is connected.')...
        makeEntry('LaserTriggerDebounceTicks', 1)...
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
% RggScan.m                                                                %
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
