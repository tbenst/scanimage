classdef SI < scanimage.interfaces.Component & most.HasMachineDataFile & most.HasClassDataFile & dynamicprops
    %SI     Top-level description and control of the state of the ScanImage application

    %% USER PROPS
    %% Acquisition duration parameters
    properties (SetObservable)
        acqsPerLoop = 1;                        % Number of independently started/triggered acquisitions when in LOOP mode
        loopAcqInterval = 10;                   % Time in seconds between two LOOP acquisition triggers, for self/software-triggered mode.
        focusDuration = Inf;                    % Time, in seconds, to acquire for FOCUS acquisitions. Value of inf implies to focus indefinitely.
    end
    
    properties
       mdlCustomProps = {};                     % Cell array indicating additional user selected properties to save to the header file. 
       extCustomProps = {};                     % Cell array indicating additional user selected properties from outside of the model to save to the header file.
    end
    
    %%% Properties enabling/disabling component functionality at top-level
    properties (SetObservable)
        imagingSystem = [];                     % string, allows the selection of the scanner using a name settable by the user in the MDF
        extTrigEnable = false;                  % logical, enabling hScan2D external triggering features for applicable GRAB/LOOP acquisitions
    end
    
    %transient because it is saved in class data file
    properties (SetObservable, Transient)
        useJsonHeaderFormat = false;
        objectiveResolution;
    end
    
    %%% ROI properties - to devolve
    properties (SetObservable, Hidden, Transient)
        lineScanParamCache;                     % Struct caching 'base' values for the ROI params of hScan2D (scanZoomFactor, scanAngleShiftFast/Slow, scanAngleMultiplierFast/Slow, scanRotation)
        acqParamCache;                          % Struct caching values prior to acquisition, set to other values for the acquisition, and restored to cached values after acquisition is complete.        
        hScannerMap;
    end
    
    properties (SetObservable, SetAccess=private, Hidden)
        acqStartTime;                           % Time at which the current acquisition started. This is not used for any purpose other than "soft" timing.
        imagingSystemChangeInProgress = false;
    end
    
    properties (SetObservable, SetAccess=private, Transient)
        acqState = 'idle';                      % One of {'focus' 'grab' 'loop' 'idle' 'point'}
    end
    
    properties (SetObservable, SetAccess=private, Hidden)
        loopAcqCounter = 0;                     % Number of grabs in acquisition mode 'loop'
        acqInitDone = false;                    % indicates the acqmode has completed initialization
        secondsCounter = 0;                     % current countdown or countup time, in seconds
        overvoltageStatus = false;              % Boolean. Shows if the system is in an over-voltage state
        hOvervoltageMsgDialog;
        hFAFErrMsgDialog;
    end
    
    %% PUBLIC API *********************************************************
    %%% Read-only component handles
    properties (SetAccess=immutable,Transient)
        hCoordinateSystems;     % scanimage.components.CoordinateSystems
        hWaveformManager;       % scanimage.components.WaveformManager handle
        hRoiManager;            % scanimage.components.RoiManager handle
        hBeams;                 % Beams handle
        hMotors;                % scanimage.components.Motors handle
        hFastZ;                 % scanimage.components.FastZ handle
        hStackManager;          % scanimage.components.StackManager handle
        hChannels;              % scanimage.components.Channels handle
        hPmts;                  % PMTs handle
        hShutters;              % scanimage.components.Shutters handle
        hDisplay;               % scanimage.components.Display handle
        hConfigurationSaver;    % scanimage.components.ConfigurationSaver handle
        hUserFunctions;         % scanimage.components.UserFunctions handle
        hWSConnector;           % WaveSurfer-Connection handle
        hMotionManager;         % scanimage.components.MotionManager handle


        hScanners = {};         % Scanners handle
        scannerNames;           % Names of available scanners
        hCycleManager;          % scanimage.components.CycleManager handle
    end
    
    properties (SetObservable, SetAccess = private, Transient)
        hScan2D;                % Handle to the scanning component
                                % NOTE: hScan2D has to be included in mdlHeaderExcludeProps if it is not hidden (otherwise it will show up in the TIFF header)
    end
 
    
    %% FRIEND PROPS
    properties (Hidden, GetAccess = {?scanimage.interfaces.Class, ?most.Model})
        %Properties that are cache prior to acq, then set to another value, and finally restored after acq abort.
        cachedAcqProps = {'hChannels.loggingEnable','hStackManager.enable','hStackManager.framesPerSlice','hScan2D.trigAcqTypeExternal','acqsPerLoop'};
        
        %Properties that are cached when clicking line scan button
        cachedLineScanProps = {'hRoiManager.scanAngleMultiplierSlow' 'hRoiManager.scanAngleMultiplierFast' 'hRoiManager.scanAngleShiftSlow' 'hRoiManager.forceSquarePixels'};
    end
    
    %% INTERNAL PROPS
    %%%Constants
    properties(Transient,Constant)
        %Properties capturing the ScanImage version number - a single number plus the service pack number
        %Snapshots between service pack releases should add/subtract 0.5 from prior service pack to signify their in-betweenness
        VERSION_MAJOR = '5.7';     % Version number
        VERSION_MINOR = '1';       % Minor release number (0 = the initial release; positive numbers = maintenance releases)
        
        VERSION_COMMIT = scanimage.util.getCommitHash(); % Git commit hash

        % SI Tiff format version number
        TIFF_FORMAT_VERSION = 4;    % Tiff format version. This should be incremented any time there is a change in how a tiff should be decoded.
        LINE_FORMAT_VERSION = 1;    % Line scanning data format version. This should be incremented any time there is a change in how line scan data should be decoded.
    end
    
    properties (Constant,Hidden)
        MAX_NUM_CHANNELS = 4;
        LOOP_TIMER_PERIOD = 1;
        DISPLAY_REFRESH_RATE = 30;                % [Hz] requested rate for refreshing images and processing GUI events
    end
    
    properties (Hidden, SetObservable)
        % User-settable runtime adjustment properties
        debugEnabled = false;                   % show/hide debug information in ScanImage.
        framesPerAcq = nan;
    end
    
    properties (Hidden, SetObservable, SetAccess=private)
        % The following need to be here to meet property binding requirements for most.Model.
        frameCounterForDisplay = 0;             % Number of frames acquired - this number is displayed to the user.
        acqInitInProgress = false;              % indicates the acqmode has completed initialization
        classDataDir = '';
        fpgaMap;
        fpgaDataScopeMap;
    end
    
    properties (Hidden, SetAccess=private)      
        hLoopRepeatTimer;
        OptionalComponents = {};                % List of loaded optional components
        addedPaths = {};                        % cell array of paths that were added to the Matlab search path by scanimage
    end
    
    properties (Hidden, SetAccess=private, Dependent)
        secondsCounterMode;                     % One of {'up' 'down'} indicating whether this is a count-up or count-down timer
    end
    
    %%% ABSTRACT PROP REALIZATION (most.Model)
    properties (Hidden, SetAccess=protected)
        mdlPropAttributes = zlclInitPropAttributes();
        mdlHeaderExcludeProps = {'hScanners' 'scannerNames' 'useJsonHeaderFormat' 'focusDuration' 'mdlCustomProps' 'extCustomProps'};
    end
    
    %%% ABSTRACT PROPERTY REALIZATIONS (most.HasMachineDataFile)
    properties (Constant, Hidden)
        %Value-Required properties
        mdfClassName = mfilename('class');
        mdfHeading = 'ScanImage';
        
        %Value-Optional properties
        mdfDependsOnClasses; %#ok<MCCPI>
        mdfDirectProp;       %#ok<MCCPI>
        mdfPropPrefix;       %#ok<MCCPI>
        
        mdfDefault = defaultMdfSection();
    end
    
    %%% ABSTRACT PROPERTY REALIZATION (scanimage.interfaces.Component)
    properties (SetAccess=protected, Hidden)
        numInstances = 0;        
    end
    
    properties (Constant, Hidden)
        COMPONENT_NAME = 'SI root object';                                % [char array] short name describing functionality of component e.g. 'Beams' or 'FastZ'
        PROP_TRUE_LIVE_UPDATE = {'focusDuration'};                         % Cell array of strings specifying properties that can be set while the component is active
        PROP_FOCUS_TRUE_LIVE_UPDATE = {};                                  % Cell array of strings specifying properties that can be set while focusing
        DENY_PROP_LIVE_UPDATE = {...                                       % Cell array of strings specifying properties for which a live update is denied (during acqState = Focus)
            'acqsPerLoop','loopAcqInterval','imagingSystem','extTrigEnable'};
        FUNC_TRUE_LIVE_EXECUTION = {};                                     % Cell array of strings specifying functions that can be executed while the component is active
        FUNC_FOCUS_TRUE_LIVE_EXECUTION = {};                               % Cell array of strings specifying functions that can be executed while focusing
        DENY_FUNC_LIVE_EXECUTION = {'scanPointBeam'};                      % Cell array of strings specifying functions for which a live execution is denied (during acqState = Focus)
    end
    
    
    
    %% LIFECYCLE
    methods (Hidden)
        function obj = SI(varargin)
            scanimage.util.checkSystemRequirements();
            
            obj = obj@most.HasMachineDataFile(true, [], varargin{:});
            obj = obj@scanimage.interfaces.Component([],true); % declares SI to root component
            
            %% DRM TRIAL CODE
                % %Do Nothing
            %% DRM TRIAL CODE END
            
            try
                obj.numInstances = 1;
                
                if isfield(obj.mdfData, 'dataDir')
                    mdfLoc = fileparts(most.MachineDataFile.getInstance.fileName);
                    classDataDirBasePath = strrep(obj.mdfData.dataDir, '[MDF]', mdfLoc);
                    obj.classDataDir = fullfile(classDataDirBasePath,obj.VERSION_MAJOR);                   
                    
                    obj.migrateConfigData();
                end
                
                baseDirectory = fileparts(which('scanimage'));
                obj.addedPaths = most.idioms.addPaths({baseDirectory});
                
                %Initialize the DAQmx adapter
                try
                    [~] = dabs.ni.daqmx.System();
                catch
                    % daqmx is not installed
                end
                
                %Initialize fpga map for sharing of FPGA resources
                obj.fpgaMap = containers.Map;
                obj.fpgaDataScopeMap = containers.Map;
                
                %Initialize non-hardware components
                obj.hCoordinateSystems = scanimage.components.CoordinateSystems(obj);
                obj.hConfigurationSaver = scanimage.components.ConfigurationSaver(obj);
                obj.hUserFunctions = scanimage.components.UserFunctions(obj);
                obj.hWaveformManager = scanimage.components.WaveformManager(obj);
                
                %Initialize Channels component
                obj.hChannels = scanimage.components.Channels(obj);
                
                %Initialize optional hardware for 'beam' modulation (e.g. Pockels) and shutters
                obj.hShutters = scanimage.components.Shutters(obj);
                obj.hBeams = scanimage.components.Beams(obj);
                
                %Initialize display component class
                obj.hDisplay = scanimage.components.Display(obj);
                
                %Open RoiManager component
                obj.hRoiManager = scanimage.components.RoiManager(obj);
                
                %Initialize optional hardware for fast-Z translation
                obj.hFastZ = scanimage.components.FastZ(obj);
                
                %Configure Scan2D Objects
                obj.hScannerMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
                
                fprintf('Initializing scanner components...');
                s2dPrep = obj.getScan2DFromMdf();
                s2dPrepFieldNames = fieldnames(s2dPrep);
                
                numResScan = 0;
                for i = 1:numel(s2dPrepFieldNames)
                    scannerName = s2dPrepFieldNames{i};
                    
                    initFunc = s2dPrep.(scannerName).initFunc;
                    type = s2dPrep.(scannerName).type;
                    
                    if strcmpi(type,'ResScan')
                        if numResScan>0
                            most.ErrorHandler.logAndReportError('Cannot instantiate more than one ResScan. Scanner ''%s'' violates this rule.',scannerName);
                            numResScan = numResScan+1;
                            continue;
                        end
                        numResScan = numResScan+1;
                    end
                    
                    try
                        % attempt to initialize Scan2D
                        obj.hScanners{end+1} = initFunc(obj,scannerName);
                        obj.hScanners{end}.stripeAcquiredCallback = @(src,evnt)obj.zzzFrameAcquiredFcn;
                    catch ME
                        most.ErrorHandler.logAndReportError('Instantiating Scanner %s failed.',scannerName);
                        most.ErrorHandler.logAndReportError(ME);
                        continue;
                    end
                    
                    obj.hScannerMap(scannerName) = obj.hScanners{end};
                    
                    propName = ['hScan_' scannerName];
                    hProp = obj.addprop(propName);
                    obj.mdlHeaderExcludeProps{end+1} = propName;                    
                    obj.(propName) = obj.hScanners{end};
                    
                    hProp.SetAccess = 'immutable';
                    
                    obj.mdlPropAttributes.(propName) = struct('Classes','most.Model');
                end
                
                fprintf('Done!\n');
                
                assert(~isempty(obj.hScanners),'No scanners defined. Exiting ScanImage.');
                
                
                %Initialize stack manager component
                obj.hStackManager = scanimage.components.StackManager(obj);
                
                %Initialize Optional Components
                obj.zprvLoadOptionalComponents();
                
                %Initialize optional motor hardware for X/Y/Z motion
                obj.hMotors = scanimage.components.Motors(obj);
                
                %Set up callback for motor errors:
                obj.hMotors.hErrorCallBack = @obj.zprvMotorErrorCbk;
                
                %Initialize optional PMT controller interface
                obj.hPmts = scanimage.components.Pmts(obj);
                
                %Initialize WaveSurfer connector
                obj.hWSConnector = scanimage.components.WSConnector(obj);
                
                %Loop timer
                obj.hLoopRepeatTimer = timer('BusyMode','drop',...
                    'Name','Loop Repeat Timer',...
                    'ExecutionMode','fixedRate',...
                    'StartDelay',obj.LOOP_TIMER_PERIOD, ...
                    'Period',obj.LOOP_TIMER_PERIOD, ...
                    'TimerFcn',@obj.zzzLoopTimerFcn);
                
                
                %Motion Manager
                obj.hMotionManager = scanimage.components.MotionManager(obj);
                
                %CycleMode manager
                obj.hCycleManager = scanimage.components.CycleManager(obj);    % isRoot == false, independentComponent == true
                
                obj.ensureClassDataFile(struct('useJsonHeaderFormat',false));
                obj.useJsonHeaderFormat = obj.getClassDataVar('useJsonHeaderFormat');
                
                obj.imagingSystem = obj.hScanners{1}.name;
            catch ME
                obj.delete();
                rethrow(ME);
            end
        end
        
        function migrateConfigData(obj)
            classDataDirBasePath = fileparts(obj.classDataDir);
            
            if exist(obj.classDataDir,'dir')
                return % class data dir for this version exists. no need to migrate
            end
            
            if ~exist(classDataDirBasePath,'dir')
                return % class data dir base path does not exist. don't know where to migrate from
            end
            
            answer = questdlg('Do you want to migrate stored settings from a different ScanImage version?',...
                              'Migrate Settings','Yes','No','No');
            switch answer
                case 'Yes'
                    srcFolder = selectMigrationSource();
                otherwise
                    srcFolder = [];
            end
            
            if ~isempty(srcFolder)
                % just copy srcFolder content into new class data dir to
                % keep it simple
                copyfile(srcFolder,obj.classDataDir);
            end
            
            %%% Nested function
            function srcFolder = selectMigrationSource()
                srcFolder = [];
                
                while true
                    % loop until user selects a valid source OR cancels
                    [~,selpath] = uigetfile(fullfile(classDataDirBasePath,'Motors_classData.mat'),'Select a Motors_classData.mat');
                    
                    if isnumeric(selpath)
                        break % user aborted
                    else
                        if exist(fullfile(selpath,'Motors_classData.mat'),'file')
                            srcFolder = selpath;
                            break;
                        else
                            f = msgbox(sprintf('Folder %s does not contain ScanImage configuration data.',selpath),'Configdata not found','warn');
                            waitfor(f);
                        end
                    end
                end
            end
        end
        
        function initialize(obj)
            %Initialize this most.Model (including its submodels), which also calls initialize() on any/all controller(s)
            obj.mdlInitialize();
            
            %Initialize optional components
            for idx = 1:numel(obj.OptionalComponents)
                hComponent = obj.(obj.OptionalComponents{idx});
                if ismethod(hComponent,'initialize')
                    hComponent.initialize();
                end
            end
            
            if ~isempty(obj.mdfData.startUpScript)
                try
                    evalin('base',obj.mdfData.startUpScript);
                catch ME
                    most.ErrorHandler.logAndReportError(ME,['Error occurred running startup script: ' ME.message]);
                end
            end
        end
        
        function exit(obj)
            try
                fprintf('Exiting ScanImage...\n');
                shutDownScript_ = obj.mdfData.shutDownScript;
                delete(obj);
                evalin('base','clear hSI hSICtl MachineDataFile');
                
                if ~isempty(shutDownScript_)
                    try
                        evalin('base',shutDownScript_);
                    catch ME
                        most.ErrorHandler.logAndReportError(ME,['Error occurred running shutdown script: ' ME.message]);
                    end
                end
                
                fprintf('Done!\n');
            catch ME
                most.ErrorHandler.logAndReportError(ME);
                fprintf('ScanImage exited with errors\n');
            end
        end
        
        function delete(obj)
            
            if obj.active
                obj.abort();
            end
            
            if most.idioms.isValidObj(obj.hUserFunctions)
                obj.hUserFunctions.notify('applicationWillClose');
            end
            
            if most.idioms.isValidObj(obj.hFastZ)
                obj.hFastZ.saveClassData(); % this is necessary, because zAlignment might be drawn from hSlmScan
            end            
            
            most.idioms.safeDeleteObj(obj.hDisplay);
            most.idioms.safeDeleteObj(obj.hShutters);
            
            for i = 1:numel(obj.hScanners)
                most.idioms.safeDeleteObj(obj.hScanner(i));
            end
            
            most.idioms.safeDeleteObj(obj.hLoopRepeatTimer);
            most.idioms.safeDeleteObj(obj.hBeams);
            most.idioms.safeDeleteObj(obj.hMotors);
            most.idioms.safeDeleteObj(obj.hFastZ);
            most.idioms.safeDeleteObj(obj.hPmts);
            most.idioms.safeDeleteObj(obj.hConfigurationSaver);
            most.idioms.safeDeleteObj(obj.hRoiManager);
            most.idioms.safeDeleteObj(obj.hStackManager);
            most.idioms.safeDeleteObj(obj.hUserFunctions);
            most.idioms.safeDeleteObj(obj.hWSConnector);
            most.idioms.safeDeleteObj(obj.hMotionManager);
            most.idioms.safeDeleteObj(obj.hCycleManager);
            most.idioms.safeDeleteObj(obj.hOvervoltageMsgDialog);
            most.idioms.safeDeleteObj(obj.hFAFErrMsgDialog);
            most.idioms.safeDeleteObj(obj.hWaveformManager);
            most.idioms.safeDeleteObj(obj.hCoordinateSystems);
            
            if ~isempty(obj.fpgaDataScopeMap)
                for s = obj.fpgaDataScopeMap.values
                    most.idioms.safeDeleteObj(s{1});
                end
                most.idioms.safeDeleteObj(obj.fpgaDataScopeMap);
            end
            
            % destruct optional components
            for i = 1:numel(obj.OptionalComponents)
                most.idioms.safeDeleteObj(obj.(obj.OptionalComponents{i}));
            end
            
            if ~isempty(obj.fpgaMap)
                for s = obj.fpgaMap.values
                    most.idioms.safeDeleteObj(s{1}.hFpga);
                end
                most.idioms.safeDeleteObj(obj.fpgaMap);
            end
        end
    end
    
    %% PROP ACCESS
    methods
        function scObj = hScanner(obj, scnnr)
        %   Returns the appropriate Scanner object, managing legacy versions
            try
                if nargin < 2
                    scObj = obj.hScan2D;
                elseif ischar(scnnr)
                    scObj = obj.hScannerMap(scnnr);
                else
                    scObj = obj.hScanners{scnnr};
                end
            catch
                scObj = [];
            end
        end
        
        function set.acqsPerLoop(obj,val)
            val = obj.validatePropArg('acqsPerLoop',val);
            if obj.componentUpdateProperty('acqsPerLoop',val)
                obj.acqsPerLoop = val;
            end
        end
        
        function set.extTrigEnable(obj,val)
            val = obj.validatePropArg('extTrigEnable',val);
            if obj.componentUpdateProperty('extTrigEnable',val)
                obj.extTrigEnable = val;
            end
        end
        
        function set.acqState(obj,val)
            assert(ismember(val,{'idle' 'focus' 'grab' 'loop' 'loop_wait' 'point'}));
            obj.acqState = val;
        end
        
        function set.focusDuration(obj,val)
            obj.validatePropArg('focusDuration',val);
            if obj.componentUpdateProperty('focusDuration',val)
                obj.focusDuration = val;
            end
        end
        
        function set.loopAcqInterval(obj,val)
            val = obj.validatePropArg('loopAcqInterval',val);
            if obj.componentUpdateProperty('loopAcqInterval',val)
                obj.loopAcqInterval = val;
            end
        end
        
        function val = get.secondsCounterMode(obj)
            switch obj.acqState
                case {'focus' 'grab'}
                    val = 'up';
                case {'loop' 'loop_wait'}
                    if isinf(obj.loopAcqInterval) || obj.hScan2D.trigAcqTypeExternal
                        val = 'up';
                    else
                        val = 'down';
                    end
                otherwise
                    val = '';
            end
        end
        
        function set.imagingSystem(obj,val)
            if obj.componentUpdateProperty('imagingSystem',val)
                
                assert(~obj.imagingSystemChangeInProgress,'Imaging system switch is already in progress.');
                
                try
                    result = regexp(val,'(.+)\((.+)\)','tokens');
                    
                    if isempty(result)
                        name = val;
                        mode = '';
                    else
                        name = strtrim(result{1}{1});
                        mode = lower(strtrim(result{1}{2}));
                    end
                    
                    if ismember(name, obj.hScannerMap.keys)
                        obj.imagingSystemChangeInProgress = true;
                        obj.hChannels.saveCurrentImagingSettings();
                        if most.idioms.isValidObj(obj.hScan2D)
                            obj.hScan2D.deinitRoutes();
                        end
                        obj.imagingSystem = name;
                        obj.hScan2D = obj.hScannerMap(name);
                        if ~isempty(mode)
                            obj.hScan2D.scanMode = mode;
                        end
                    else
                        error('Invalid imaging system selection.');
                    end
                    
                    % Crude workaround to ensure triggering is only enabled if
                    % trigger terminals are defined
                    % Todo: Cach extTrigEnable for LinScan and ResScan and
                    % restore value when changing imagingSystem
                    obj.extTrigEnable = false;
                    
                    % Init DAQ routes and park scanner
                    try
                        obj.hScan2D.reinitRoutes();
                    catch ME
                        obj.hShutters.shuttersTransitionAll(false);
                        rethrow(ME);
                    end
                    obj.hShutters.shuttersTransitionAll(false);
                    
                    % Ensure valid scan type selection
                    if ~isa(obj.hScan2D,'scanimage.components.scan2d.LinScan') && obj.hRoiManager.isLineScan
                        obj.hRoiManager.scanType = 'frame';
                    end
                    
                    % park all scanners
                    cellfun(@(x)x.parkScanner(), obj.hScanners, 'UniformOutput', false);
                    
                    % Re-bind depends-on listeners
                    obj.reprocessDependsOnListeners('hScan2D');
                    
                    % Invoke channel registration in Channel component.
                    obj.hChannels.registerChannels();
                    
                    
                    % coerce to scanning modes for this scanner
                    obj.hRoiManager.scanType = obj.hRoiManager.scanType;
                    
                    % Update file counter
                    obj.hScan2D.logFileStem = obj.hScan2D.logFileStem;
                    obj.imagingSystemChangeInProgress = false;
                    
                    % update display
                    obj.hDisplay.resetActiveDisplayFigs(false);
                    
                    % Coerce fastz mode
                    obj.hFastZ.enable = obj.hFastZ.enable;
                    
                    % reset waveforms
                    obj.hWaveformManager.resetWaveforms(); % this is necessary to load optimized waveforms from the correct cache
                catch ME
                    obj.imagingSystemChangeInProgress = false;
                    ME.rethrow();
                end
            end
        end
        
        function v = get.scannerNames(obj)
            v = cellfun(@(s)s.name,obj.hScanners,'UniformOutput',false);
        end
        
        function set.useJsonHeaderFormat(obj,val)
            val = obj.validatePropArg('useJsonHeaderFormat',val);
            obj.useJsonHeaderFormat = val;
            
            if obj.mdlInitialized
                obj.setClassDataVar('useJsonHeaderFormat',val);
            end
        end
        
        function v = get.objectiveResolution(obj)
            v = obj.mdfData.objectiveResolution;
        end
        
        function set.objectiveResolution(obj,v)
            v = obj.validatePropArg('objectiveResolution',v);
            obj.mdfData.objectiveResolution = v;
            mdf = most.MachineDataFile.getInstance();
            if mdf.isLoaded
				mdf.writeVarToHeading('ScanImage','objectiveResolution',v);
            end
        end
    end
    
    %% STATIC METHODS
    methods (Static)
        function cd()
            % cd changes the working directory to the ScanImage
            % installation directory
            scanimage.util.checkSystemRequirements();
            cd(scanimage.util.siRootDir());
        end
               
        function str = version()
            % version outputs the ScanImage version and commit hash
            
            scanimage.util.checkSystemRequirements();
            
            version_commit = scanimage.SI.VERSION_COMMIT;
            version_commit(11:end) = []; % get short hash
            str_ = sprintf('ScanImage(R) %s-%s %s',scanimage.SI.VERSION_MAJOR,scanimage.SI.VERSION_MINOR,version_commit);
            
            if nargout > 0
                str = str_; % only assign output if nargout > 0. this suppresses 'ans' output in command window
            else
                fprintf('\n%s\n\n',str_);
            end
        end 
    end    
    
    %% USER METHODS
    methods
        function str = getHeaderString(obj,customProps)
            if nargin < 2 || isempty(customProps)
                customProps = [];
            end
            
            if obj.useJsonHeaderFormat
                s = obj.mdlGetHeaderStruct();
                str = most.json.savejson('SI',s,'tab','  ');
            else
                if ~isempty(customProps)
                    str = strrep(obj.mdlGetHeaderString('include',customProps),'scanimage.SI.','SI.');
                else
                    str = strrep(obj.mdlGetHeaderString(),'scanimage.SI.','SI.');
                end
            end
        end
        
        function str = getRoiDataString(obj)
            s.RoiGroups.imagingRoiGroup = obj.hRoiManager.currentRoiGroup.saveobj;
            str = most.json.savejson('',s,'tab','  ');
        end
        
        
        function startFocus(obj)
            % STARTFOCUS   Starts the acquisition in "FOCUS" mode
            obj.start('focus');
        end
        
        function startGrab(obj)
            % STARTGRAB   Starts the acquisition in "GRAB" mode
            obj.start('grab');
        end
        
        function startLoop(obj)
            % STARTLOOP   Starts the acquisition in "LOOP" mode
            obj.start('loop');
            if obj.acqsPerLoop > 1
                start(obj.hLoopRepeatTimer);
            end
        end
        
        function startCycle(obj)
            % STARTCYCLE   Starts the acquisitoin through the CycleManager component
            obj.hCycleManager.start();
        end

        
        function scanPointBeam(obj,beams)
            % SCANPOINTBEAM Points scanner at center of FOV, opening shutter and with specified beams ON
            %   obj.scanPointBeam           Turn on all beams
            %   obj.scanPointBeam(beams)    Turn on the input collection of beams.
            
            if obj.componentExecuteFunction('scanPointBeam')
                if nargin < 2
                    beams = 1:obj.hBeams.totalNumBeams; % if argument 'beams' is omitted, activate all beams
                end
                
                obj.acqState = 'point';
                obj.acqParamCache = struct();
                
                obj.hScan2D.centerScanner();
                obj.hShutters.shuttersTransition(obj.hScan2D.mdfData.shutterIDs, true); % Opens linked shutters
                % beams need to be controlled with direct mode
                
                obj.acqInitDone = true;
            end
        end
    end
    
    %%% PUBLIC METHODS (Scan Parameter Caching)
    methods        
        function lineScanRestoreParams(obj,~)
            % LINESCANRESTOREPARAMS  Set ROI scan parameters (zoom,scanAngleMultiplier) to cached values.
            %   obj.lineScanRestoreParams(params)
            %
            % If no values are cached, restores the scan parameters stored in currently loaded CFG file.
            cachedProps = obj.cachedLineScanProps;
            
            if ~isempty(obj.lineScanParamCache)
                for i=1:length(cachedProps)
                    tempName = strrep(cachedProps{i},'.','_');
                    val = obj.lineScanParamCache.(tempName);
                    zlclRecursePropSet(obj,cachedProps{i},val);
                end
            else
                cfgfile = obj.hConfigurationSaver.cfgFilename;
                
                resetFailProps = {};
                if exist(cfgfile,'file')==2
                    cfgPropSet = obj.mdlLoadPropSetToStruct(cfgfile);
                    
                    for i=1:length(cachedProps)
                        if zlclRecurseIsField(cfgPropSet,cachedProps{i})
                            val = zlclRecursePropGet(cfgPropSet,cachedProps{i});
                            zlclRecursePropSet(obj,cachedProps{i},val);
                        else
                            resetFailProps{end+1} = cachedProps{i};   %#ok<AGROW>
                        end
                    end
                end
                
                if ~isempty(resetFailProps)
                    warning('SI:scanParamNotReset',...
                        'One or more scan parameters (%s) were not reset to base or config file value.',most.util.toString(resetFailProps));
                end
            end
        end
        
        function lineScanCacheParams(obj)
            % LINESCANCACHEPARAMS Caches scan parameters (zoom, scan angle multiplier) which can be recalled by scanParamResetToBase() method
            for i=1:numel(obj.cachedLineScanProps)
                val = zlclRecursePropGet(obj,obj.cachedLineScanProps{i});
                tempName = strrep(obj.cachedLineScanProps{i},'.','_');
                obj.lineScanParamCache.(tempName) = val;
            end
        end
    end

    %%% HIDDEN METHODS
    methods (Hidden)
        function zzzRestoreAcqCacheProps(obj)
            try
                cachedProps = obj.cachedAcqProps;
                for i=1:length(cachedProps)
                    tempName = strrep(cachedProps{i},'.','_');
                    if isfield(obj.acqParamCache,tempName)
                        val = obj.acqParamCache.(tempName);
                        zlclRecursePropSet(obj,cachedProps{i},val);
                    end
                end
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
        end
        
        function zzzSaveAcqCacheProps(obj)
            cachedProps = obj.cachedAcqProps;
            for i=1:length(cachedProps)
                tempName = strrep(cachedProps{i},'.','_');
                val = zlclRecursePropGet(obj,cachedProps{i});
                obj.acqParamCache.(tempName) = val;
            end
        end
    end
    
    methods (Access = protected, Hidden)
        % component overload function
        function val = componentGetActiveOverride(obj,~)
            isIdle = strcmpi(obj.acqState,'idle');
            val = ~isIdle && obj.acqInitDone;
        end
    end
    
    %% FRIEND METHODS
    %%% Super-user Methods
    methods (Hidden)
        function val = getSIVar(obj,varName)
            val = eval(['obj.' varName]);
        end
        
        function hFpga = initVdaq(obj,vdaqId,simulate,passive)
            if nargin < 3
                simulate = false;
            end
            if nargin < 4
                passive = false;
            end
            if obj.fpgaMap.isKey(vdaqId)
                hFpga = obj.fpgaMap(vdaqId).hFpga;
            else
                vdaqNum = str2double(vdaqId(5:end));
                hFpga = scanimage.fpga.vDAQ_SI(vdaqNum,simulate);
                if ~passive
                    hFpga.run();
                end
                
                s = struct('hFpga',hFpga,'fpgaType','vDAQ','digitizerType','vDAQ','bitfilePath',hFpga.bitfilePath);
                obj.fpgaMap(vdaqId) = s;
            end
        end
        
        function device = initIfVdaq(obj,device,varargin)
            if dabs.vidrio.rdi.Device.isRdiDeviceName(device)
                device = obj.initVdaq(device,varargin{:});
            end
        end
    end
    
    %% INTERNAL METHODS
    methods (Hidden)
        function zzzShutdown(obj, soft, completedAcquisitionSuccessfully)
            if nargin < 3 || isempty(completedAcquisitionSuccessfully)
                completedAcquisitionSuccessfully = false;
            end
            
            try
                obj.acqInitDone = false;
                
                %Close shutters for stop acquisition.
                obj.hShutters.shuttersTransition(obj.hScan2D.mdfData.shutterIDs, false);  % Close linked shutters, should this close all shutters since it is shutdown?
                
                %Stop the imaging component
                obj.hScan2D.abort(soft);
                
                %Stop the Pmts component
                obj.hPmts.abort();
                
                obj.hWaveformManager.abort();
                
                
                %Abort RoiManager
                obj.hRoiManager.abort();
                
                obj.hMotionManager.abort();

                
                %Set beams to standby mode for next acquisition.
                obj.hBeams.abort();
                
                %Stop the loop repeat timer.
                stop(obj.hLoopRepeatTimer);
                
                %Set display to standby mode for next acquisition.
                obj.hDisplay.abort(soft);
                
                %Put pmt controller in idle mode so status is periodically updated
                obj.hPmts.abort();
                
                obj.hFastZ.abort();
                
                %Wait for any pending moves to finish, move motors to home position
                obj.hStackManager.abort();
                
                %Stop the Channel Manager as a metter of course. Currently doesn't do anything.
                obj.hChannels.abort();
                
                %Change the acq State to idle.
                obj.acqState = 'idle';
                
                obj.hWSConnector.abort(completedAcquisitionSuccessfully);
                
                obj.zzzRestoreAcqCacheProps();
            catch ME
                %Change the acq State to idle.
                obj.acqState = 'idle';
                obj.acqInitDone = false;
                
                ME.rethrow;
            end
        end
        
        function zzzEndOfAcquisitionMode(obj)
            obj.zzzEndOfAcquisition();
            
            %This function is called at the end of FOCUS, GRAB, and LOOP acquisitions.            
            obj.hCycleManager.acqModeCompleted(); % This function does nothing.
            
            abortCycle = false;
            completedAcquisitionSuccessfully = true;
            obj.abort([],abortCycle,completedAcquisitionSuccessfully);
            
            % Moved after the abort command so user functions can call
            % startLoop or startGrab at the end of an acquisition.
            obj.hUserFunctions.notify('acqModeDone');
        end
        
        function zzzEndOfAcquisition(obj)            
            stackDone = obj.hStackManager.endOfAcquisition();
            
            if stackDone
                obj.hUserFunctions.notify('acqDone');
                
                %Handle end of GRAB or LOOP Repeat
                obj.loopAcqCounter = obj.loopAcqCounter + 1;
                
                %Update logging file counters for next Acquisition
                if obj.hChannels.loggingEnable
                    obj.hScan2D.logFileCounter = obj.hScan2D.logFileCounter + 1;
                end
                
                %For Loop, restart or re-arm acquisition
                if isequal(obj.acqState,'loop')
                    obj.acqState = 'loop_wait';
                else
                    obj.zzzShutdown(false);
                end
            end
        end
    end
    
    %%% Callbacks
    methods (Hidden)
        function zzzFrameAcquiredFcn(obj,~,~) % Executes on Every Stripe as well.
            try
                %%%%%%%%%%%%%%% start of frame batch loop %%%%%%%%%%%%%%%%%%%
                maxBatchTime = 1/obj.DISPLAY_REFRESH_RATE;
                
                readSuccess = false;
                processFrameBatch = true;
                loopStart = tic;
                while processFrameBatch && toc(loopStart) <= maxBatchTime;
                    [readSuccess,stripeData] = obj.hScan2D.readStripeData();
                    if ~readSuccess;break;end % tried to read from empty queue
                    
                    % Stop processing frames once the number of frames remaining in this batch is zero
                    processFrameBatch = stripeData.stripesRemaining > 0;
                    
                    %**********************************************************
                    %HANDLE OVER-VOLTAGE CONDITION IF DETECTED.
                    %**********************************************************
                    if stripeData.overvoltage && ~obj.overvoltageStatus && ~most.idioms.isValidObj(obj.hOvervoltageMsgDialog)% Only fire this event once
                        obj.hUserFunctions.notify('overvoltage');
                        obj.overvoltageStatus = true;
                        most.idioms.dispError('DC Overvoltage detected. <a href ="matlab: hSI.hScan2D.hAcq.resetDcOvervoltage();disp(''Overvoltage reset successfully'')">RESET DIGITIZER</a>\n');
                        most.idioms.safeDeleteObj(obj.hOvervoltageMsgDialog);
                        obj.hOvervoltageMsgDialog = most.gui.nonBlockingDialog('Overvoltage deteced',...
                            sprintf('The PMT signal exceeded the input range of the digitizer.\nThe input coupling changed from DC to AC to protect the digitizer.\n'),...
                            { {'Reset Digitizer',@(varargin)obj.hScan2D.hAcq.hFpga.resetDcOvervoltage()},...
                            {'Abort Acquisition',@(varargin)obj.abort()},...
                            {'Ignore',[]} },...
                            'Position',[0,0,350,150]);
                    elseif ~stripeData.overvoltage
                        obj.overvoltageStatus = false;
                        %                     if ~isempty(obj.hOvervoltageMsgDialog)
                        %                         most.idioms.safeDeleteObj(obj.hOvervoltageMsgDialog);
                        %                         obj.hOvervoltageMsgDialog =  [];
                        %                     end
                    end
                    
                    %**********************************************************
                    %HANDLE ACCOUNTING FOR FIRST FRAME OF ACQUISITION
                    %**********************************************************
                    if isequal(obj.acqState,'loop_wait')
                        obj.acqState = 'loop'; %Change acquisition state to 'loop' if we were in a 'loop_wait' mode.
                        obj.zprvResetAcqCounters();
                    end
                    
                    if stripeData.frameNumberAcq(1) == 1 && stripeData.startOfFrame
                        %Reset counters if this is the first frame of an acquisition.
                        obj.hUserFunctions.notify('acqStart');
                        %Only reset countdown timer if we are not currently in
                        %a slow stack grab.
                        if ~obj.hStackManager.isSlowZ
                            obj.zzStartSecondsCounter();
                        end
                    end
                    
                    % handle stacks
                    stripeData = obj.hStackManager.stripeAcquired(stripeData);
                    
                    %**********************************************************
                    %SEND FRAMES TO DISPLAY BUFFER
                    %**********************************************************
                    % Calling Integration Manager update
                    if stripeData.endOfFrame
                        stripeData = obj.hMotionManager.estimateMotion(stripeData);
                    end
                    
                    obj.hDisplay.averageStripe(stripeData);
                    
                    if stripeData.endOfFrame
                        obj.hUserFunctions.notify('frameAcquired');
                    end
                    %**********************************************************
                    %ACQUISITION MODE SPECIFIC BEHAVIORS
                    %**********************************************************
                    switch obj.acqState
                        case 'focus'
                            if etime(clock, obj.acqStartTime) >= obj.focusDuration
                                obj.zzzEndOfAcquisition();
                            end
                        case {'grab' 'loop'}
                            %Handle signals from FPGA
                            if stripeData.endOfAcquisitionMode
                                obj.zzzEndOfAcquisitionMode();
                            elseif stripeData.endOfAcquisition
                                obj.zzzEndOfAcquisition();
                            end
                        case {'idle'}
                            %Do nothing...should this be an error?
                    end
                end
                %%%%%%%%%%%%%%% end of frame batch loop %%%%%%%%%%%%%%%%%%%
                
                if readSuccess
                    %**********************************************************
                    % DRAW FRAME BUFFER
                    %**********************************************************
                    obj.hDisplay.displayChannels();
                    
                    %**********************************************************
                    %UPDATE FRAME COUNTERS
                    %**********************************************************
                    obj.frameCounterForDisplay = obj.hStackManager.framesDone;
                end
                
            catch ME
                most.ErrorHandler.logAndReportError(ME,'An error occurred during frame processing. Datalogging to disk was uninterrupted but display and advanced processing failed.');
                
                if ~most.idioms.isValidObj(obj.hFAFErrMsgDialog)
                    obj.hFAFErrMsgDialog = most.gui.nonBlockingDialog('Frame Processing Error',...
                            sprintf(['An error occurred during frame processing. Datalogging to disk was '...
                            'uninterrupted but display and advanced processing failed. If this problem persists '...
                            'contact support and include a support report.']),...
                            { {'Abort Acquisition',@(varargin)obj.abort()},...
                              {'Generate Support Report',@(varargin)scanimage.util.generateSIReport(0)},...
                              {'Ignore',[]} },...
                            'Position',[0,0,500,120]);
                end
            end
            
            % This has to occur at the very end of the frame acquired function
            % signal scan2d that we are ready to receive new data
            obj.hScan2D.signalReadyReceiveData();
        end
        
        function zzzLoopTimerFcn(obj,src,~)
            obj.zprvUpdateSecondsCounter();
            
            if ~obj.hScan2D.trigAcqTypeExternal && ismember(obj.acqState,{'loop_wait'})
                if floor(obj.secondsCounter) <= 0
                    obj.zprvResetAcqCounters();
                    
                    obj.hScan2D.trigIssueSoftwareAcq();
                    stop(src);
                    
                    start(src);
                    obj.secondsCounter = obj.loopAcqInterval;
                end
            elseif obj.secondsCounter == 0
                most.idioms.warn('Software timer went to zero during active loop. Waiting until end of current acq before issuing software trigger.');
            end
        end
    end
    
    %%% TBD
    methods (Hidden)        
        %% Timer functions
        function zprvUpdateSecondsCounter(obj)
            % Simple countup/countdown timer functionality.
            switch obj.acqState
                case 'focus'
                    obj.secondsCounter = obj.secondsCounter + 1;
                case 'grab'
                    obj.secondsCounter = obj.secondsCounter + 1;
                case 'loop_wait'
                    switch obj.secondsCounterMode
                        case 'up'
                            obj.secondsCounter = obj.secondsCounter + 1;
                        case 'down'
                            obj.secondsCounter = obj.secondsCounter - 1;
                    end
                case 'loop'
                    switch obj.secondsCounterMode
                        case 'up'
                            obj.secondsCounter = obj.secondsCounter + 1;
                        case 'down'
                            obj.secondsCounter = obj.secondsCounter - 1;
                    end
                otherwise
            end
        end
        
        function zzStartSecondsCounter(obj)
            if ismember(obj.acqState,{'focus','grab'}) || (ismember(obj.acqState,{'loop','loop_wait'}) && obj.hScan2D.trigAcqTypeExternal)
                obj.secondsCounter = 0;
            else
                obj.secondsCounter = obj.loopAcqInterval;
            end
        end
        
        function zprvResetAcqCounters(obj)
            
            %If in loop acquisition, do not reset the loopAcqCounter.
            if ~strcmpi(obj.acqState,'loop') && ~strcmpi(obj.acqState,'loop_wait')
                obj.loopAcqCounter = 0;
            end
            
            %Reset Frame Counter.
            obj.frameCounterForDisplay = 0;
        end
        
        function zprvMotorErrorCbk(obj,varargin)
            if obj.isLive()
                most.idioms.dispError('Motor error occurred. Aborting acquisition.\n');
                obj.abort();
            end
        end
        
        function zprvLoadOptionalComponents(obj)
            for i = 1:numel(obj.mdfData.components)
                component = obj.mdfData.components{i};
                
                if ischar(component)
                    if exist(component,'class')
                        componentName = component;
                    else
                        most.idioms.warn(['Optional component ''' component ''' not found. Make sure it is a class on the current path.']);
                    end
                elseif isa(component, 'function_handle')
                    componentName = func2str(component);
                else
                    most.idioms.warn('Invalid entry for optional component. Each item should be a string containing a class name or a function handle that takes hSI as an argument and returns an object.');
                    continue;
                end
                
                try
                    hComponent = feval(component,obj);
                    if most.idioms.isValidObj(hComponent)
                        componentName = class(hComponent);
                        dots = strfind(componentName,'.');
                        if ~isempty(dots)
                            componentName = componentName(dots(end)+1:end);
                        end
                        
                        componentHandleName = ['h' componentName];
                        
                        hProp = obj.addprop(componentHandleName);
                        obj.OptionalComponents{end+1} = componentHandleName;
                        obj.(componentHandleName) = hComponent;
                        
                        hProp.SetAccess = 'immutable';
                        hProp.Transient = true;
                    else
                        most.idioms.warn(['Failed to load optional component ''' componentName '''.']);
                    end
                catch ME
                    try
                        most.idioms.warn(['Loading optional component ''' componentName ''' failed with error:']); % if componentName is invalid this can throw
                    catch
                    end
                    most.ErrorHandler.logAndReportError(ME);
                end
            end
        end
        
        function tf = isLive(obj)
            tf = ismember(obj.acqState,{'focus' 'grab' 'loop'});
        end
        
        function s2dPrepList = getScan2DFromMdf(obj)
            % find all scanning systems
            mdf = most.MachineDataFile.getInstance;
            hdgs = {mdf.fHData.heading};
            
            %enumerate scan2d types
            s2dp = 'scanimage/components/scan2d';
            list = what(s2dp);
            list = list(1); % workaround for sparsely occuring issue where list is a 2x1 structure array, where the second element is empty
            s2dp = [strrep(s2dp,'/','.') '.'];
            names = cellfun(@(x)[s2dp x(1:end-2)],list.m,'UniformOutput',false);
            r = cellfun(@(x){eval(strcat(x,'.mdfHeading')) str2func(x)},names,'UniformOutput',false);
            r = horzcat(r{:});
            s2dMap = struct(r{:});
            s2dMdfHdgs = fieldnames(s2dMap);
            
            % if this is a legacy mdf get the scanner list
            if isfield(obj.mdfData, 'scannerNames')
                scanners = obj.mdfData.scannerNames;
            else
                scanners = {};
            end
            
            % search the mdf for each scan2d type
            s2dPrepList = struct;
            
            scannerHeadings = regexp(hdgs,'(.+)\((.+)\)','tokens');
            isScanner = ~cellfun(@isempty,scannerHeadings);
            
            for scannerHeading = scannerHeadings(isScanner)
                type = strtrim(scannerHeading{1}{1}{1});
                name = strtrim(scannerHeading{1}{1}{2});
                
                if ismember(type,s2dMdfHdgs) && (isempty(scanners) || ismember(name, scanners))
                    if isfield(s2dPrepList,name)
                        most.idioms.warn('Scanner names must be unique. ''%s'' is duplicated.',name);
                    elseif isvarname(name)
                        s2dPrepList.(name).initFunc = s2dMap.(type);
                        s2dPrepList.(name).type = type;
                    else
                        most.idioms.warn('Invalid scanner name. Names must be alphanumeric. ''%s'' will not be initialized',name);
                    end
                end
            end
        end
    end
    
    %%% ABSTRACT METHOD IMPLEMENTATONS (scanimage.interfaces.Component)
    methods (Access = protected)
        %Handle all component coordination at start
        function componentStart(obj, acqType)
            assert(~obj.imagingSystemChangeInProgress,'Cannot start acquisition while imaging system switch is in progress.');
            
        %   Starts the acquisition given the selected mode and propagates the event to all components
            switch lower(acqType)
                case 'focus'
                    obj.hUserFunctions.notify('focusStart');
                case 'grab'
                    obj.hUserFunctions.notify('acqModeStart');
                case 'loop'
                    obj.hUserFunctions.notify('acqModeStart');
                    obj.hLoopRepeatTimer.TasksToExecute = Inf;
                otherwise
                    most.idioms.warn('Unknown acquisition type. Assuming ''focus''');
                    acqType = 'focus';
                    obj.hUserFunctions.notify('focusStart');
            end            
            
            if isempty(obj.hChannels.channelDisplay) && isempty(obj.hChannels.channelSave)
                most.idioms.dispError('Error: At least one channel must be selected for display or logging\n');
                return;
            end
            
            try
                assert(ismember(acqType, {'focus' 'grab' 'loop'}), 'Cannot start unknown acqType.');
                obj.acqState = acqType;
                obj.acqInitInProgress = true;
                %TODO: implement 'point'

                %Initialize component props (accounting for mode etc)
                obj.zzzSaveAcqCacheProps();
                
                switch acqType
                    case 'focus'
                        obj.hStackManager.enable = false;
                        obj.hStackManager.framesPerSlice = Inf;
                        obj.hChannels.loggingEnable = false;
                        obj.extTrigEnable = false;
                        obj.acqsPerLoop = 1;
                    case 'grab'
                        obj.acqsPerLoop = 1;
                    case 'loop'
                        % no-op
                end
                
                if strcmpi(acqType,'focus')                
                end
                
                zzzResetAcqTransientVars();
                
                obj.hStackManager.start();
                obj.hRoiManager.start();
                obj.hPmts.start();
                
                armScan2D();
                
                %Open shutter but do not wait. Plenty of processing to do while shutter is opening
                obj.hShutters.shuttersTransition(obj.hScan2D.mdfData.shutterIDs, true); % open linked shutter
                
                obj.hWaveformManager.updateWaveforms();
                obj.hWaveformManager.start();
                zzzInitializeLogging(); % header props need to be generated after updateWaveforms to capture waveformManager's optimizedScanners property

                %Start each SI component
                obj.hChannels.start();
                obj.hDisplay.start();
                obj.hBeams.start();
                obj.hFastZ.start();
                obj.hMotionManager.start();
                obj.hScan2D.start();
                
                %Initiate acquisition
                obj.zzStartSecondsCounter();
                obj.acqStartTime = clock();
                obj.acqInitDone = true;
                
                obj.hScan2D.signalReadyReceiveData();
                obj.acqInitInProgress = false;
                if any(ismember(acqType,{'loop' 'grab'}))
                    obj.hUserFunctions.notify('acqModeArmed');
                end
                
                obj.hShutters.waitForTransitionComplete();
                
                zzzIssueTrigger();
                
                obj.hWSConnector.start(acqType);
            catch ME
                obj.acqState = 'idle';
                obj.acqInitInProgress = false;                
                obj.zzzRestoreAcqCacheProps();
                
                ME.rethrow();
            end
            
            %%% LOCAL FUNCTION DEFINITIONS
            function zzzIssueTrigger()
                %Issues software timed
                softTrigger = (ismember(obj.acqState,{'grab' 'loop'}) && (~obj.hScan2D.trigAcqTypeExternal || ~obj.extTrigEnable))...
                    || isequal(obj.acqState, 'focus');
                
                if softTrigger
                    obj.hScan2D.trigIssueSoftwareAcq(); % ignored if obj.hAcq.triggerTypeExternal == true
                end
            end
            
            function zzzResetAcqTransientVars()
                obj.acqInitDone = false;
                obj.loopAcqCounter = 0;
                obj.overvoltageStatus = false;
                
                most.idioms.safeDeleteObj(obj.hOvervoltageMsgDialog);
                obj.hOvervoltageMsgDialog =  [];
                most.idioms.safeDeleteObj(obj.hFAFErrMsgDialog);
                obj.hFAFErrMsgDialog =  [];
                
                obj.zprvResetAcqCounters(); %Resets /all/ counters
            end
            
            function armScan2D()
                if obj.hScan2D.channelsAutoReadOffsets
                    obj.hScan2D.measureChannelOffsets();
                end
                 
                obj.hScan2D.arm();
            end
            
            function zzzInitializeLogging()
                %Set the hScan2D (hidden) logging props
                if obj.hChannels.loggingEnable
                    modelProps = obj.mdlCustomProps;
                    externalProps = obj.extCustomProps;
                    
                    if ~isempty(modelProps)
                        if ~iscell(modelProps)
                            modelProps = [];
                        end
                    end
                    
                    if ~isempty(obj.extCustomProps)
                        if ~iscell(obj.extCustomProps)
                            externalProps = [];
                        else
                           externalProps = most.util.processExtCustomProps(externalProps); 
                        end
                    end
                    if ~isempty(externalProps)
                        hdrBuf = [uint8(obj.getHeaderString(modelProps)) uint8(externalProps) 0];
                    else
                        hdrBuf = [uint8(obj.getHeaderString(modelProps)) 0];
                    end
                    hdrBufLen = length(hdrBuf);
                    

                    hdrBuf = [hdrBuf uint8(obj.getRoiDataString()) 0];

                    
                    pfix = [1 3 3 7 typecast(uint32(obj.TIFF_FORMAT_VERSION),'uint8') typecast(uint32(hdrBufLen),'uint8') typecast(uint32(length(hdrBuf)-hdrBufLen),'uint8')];
                    obj.hScan2D.tifHeaderData = [pfix hdrBuf]'; % magic number, format version, header byte count, roi data byte count, data
                    obj.hScan2D.tifHeaderStringOffset = length(pfix); % magic number, format version, byte count, hdrdata
                    
                    obj.hScan2D.tifRoiDataStringOffset = length(pfix) + hdrBufLen; % magic number, format version, byte count, hdrdata, roidata
                end
            end
        end
        
        function componentAbort(obj,soft,abortCycle,completedAcquisitionSuccessfully)
            % COMPONENTABORT Aborts the acquisition, affecting active components and sending related events
            %   obj.componentAbort         Hard shutdown of the microscope
            %
            % Aborts any running task or acquisition using this component.
            %
            if nargin < 2 || isempty(soft)
                soft = false;
            end
            if nargin < 3 || isempty(abortCycle)
                abortCycle = ~soft;
            end
            if nargin < 4 || isempty(completedAcquisitionSuccessfully)
                completedAcquisitionSuccessfully = false;
            end
            
            obj.hUserFunctions.notify('acqAbort');
            cachedAcqState = obj.acqState;
                        
            obj.zzzShutdown(soft,completedAcquisitionSuccessfully);
            
            %Update logging file counters for next Acquisition
            if ismember(cachedAcqState,{'grab' 'loop'}) && obj.hChannels.loggingEnable
                obj.hScan2D.logFileCounter = obj.hScan2D.logFileCounter + 1;
            end
            
            %Restore cached acq state (only in focus mode)
            if ismember(cachedAcqState,{'focus'})
                obj.hUserFunctions.notify('focusDone');
            end
            
            if abortCycle
                obj.hCycleManager.abort();
            elseif ~soft
                obj.hCycleManager.iterationCompleted();
            end
        end
    end
end

 %% LOCAL (after classdef)
function val = zlclRecurseIsField(obj, prop)
    [ basename, propname ] = strtok(prop,'.'); % split the basename of the property from the propname (if such a difference exists)
    if ~isempty(propname)
        val = zlclRecurseIsField(obj.(basename),propname(2:end));
    else
        val = isfield(obj,prop);
    end
end

function val = zlclRecursePropGet(obj, prop)
    [ basename, propname ] = strtok(prop,'.'); % split the basename of the property from the propname (if such a difference exists)
    if ~isempty(propname)
        val = zlclRecursePropGet(obj.(basename),propname(2:end));
    else
        val = obj.(prop);
    end
end

function zlclRecursePropSet(obj, prop, val)
    [ basename, propname ] = strtok(prop,'.'); % split the basename of the property from the propname (if such a difference exists)
    if ~isempty(propname)
        zlclRecursePropSet(obj.(basename),propname(2:end),val);
    else
        obj.(prop) = val;
    end
end

function s = zlclInitPropAttributes()
    %At moment, only application props, not pass-through props, stored here -- we think this is a general rule
    %NOTE: These properties are /ordered/..there may even be cases where a property is added here for purpose of ordering, without having /any/ metadata.
    %       Properties are initialized/loaded in specified order.
    %
    s = struct();

    %%% Acquisition
    s.acqsPerLoop = struct('Classes','numeric','Attributes',{{'scalar' 'positive' 'integer' 'finite'}});
    s.extTrigEnable = struct('Classes','binaryflex','Attributes',{{'scalar'}});

    s.focusDuration = struct('Range',[1 inf]);
    s.loopAcqInterval = struct('Classes','numeric','Attributes',{{'scalar','positive','integer','finite'}});
    s.useJsonHeaderFormat = struct('Classes','binaryflex','Attributes',{{'scalar'}});
    s.objectiveResolution = struct('Classes','numeric','Attributes',{{'scalar' 'positive' 'finite' 'nonnan'}});

    s.hMotionManager = struct('Classes','most.Model');

    %%% Submodel/component props
    s.hWaveformManager = struct('Classes','most.Model');
    s.hShutters = struct('Classes','most.Model');
    s.hChannels = struct('Classes','most.Model');
    s.hMotors   = struct('Classes','most.Model');
    s.hBeams    = struct('Classes','most.Model');
    s.hFastZ    = struct('Classes','most.Model');
    s.hDisplay  = struct('Classes','most.Model');
    s.hRoiManager = struct('Classes','most.Model');
    s.hConfigurationSaver = struct('Classes','most.Model');
    s.hUserFunctions = struct('Classes','most.Model');
    s.hStackManager = struct('Classes','most.Model');
    s.hWSConnector  = struct('Classes','most.Model');
    s.hPmts = struct('Classes','most.Model');
    s.hMotionManager = struct('Classes','most.Model');
	s.hCoordinateSystems = struct('Classes','most.Model');
end

function s = defaultMdfSection()
    s = [...
        makeEntry()... % blank line
        makeEntry('Global microscope properties')... % comment only
        makeEntry('objectiveResolution',15,'Resolution of the objective in microns/degree of scan angle')...
        ...
        makeEntry()... % blank line
        makeEntry('Simulated mode')... % comment only
        makeEntry('simulated',false,'Boolean for activating simulated mode. For normal operation, set to ''false''. For operation without NI hardware attached, set to ''true''.')...
        ...
        makeEntry()... % blank line
        makeEntry('Optional components')... % comment only
        makeEntry('components',{{}},'Cell array of optional components to load. Ex: {''dabs.thorlabs.ECU1'' ''dabs.thorlabs.BScope2''}')...
        ...
        makeEntry()... % blank line
        makeEntry('Data file location')... % comment only
        makeEntry('dataDir','[MDF]\ConfigData','Directory to store persistent configuration and calibration data. ''[MDF]'' will be replaced by the MDF directory')...
        ...
        makeEntry()... % blank line
        makeEntry('Custom Scripts')... % comment only
        makeEntry('startUpScript','','Name of script that is executed in workspace ''base'' after scanimage initializes')...
        makeEntry('shutDownScript','','Name of script that is executed in workspace ''base'' after scanimage exits')...
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
% SI.m                                                                     %
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
