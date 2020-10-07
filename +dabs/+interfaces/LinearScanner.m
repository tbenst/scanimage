classdef LinearScanner < handle
    properties
        name = '';
        travelRange;
        parkPosition = -9;
        daqOutputRange;
    end
    
    properties
        simulated = false;
        
        hFpga;
        hFpgaDaq;
        
        controlDevice;
        
        positionDeviceName;
        positionChannelID;
        
        feedbackDeviceName;
        feedbackChannelID;
        feedbackTermCfg = 'Differential';
        
        offsetDeviceName;
        offsetChannelID;
        
        position2VoltFcn = [];
        volt2PositionFcn = [];
        voltsPerDistance = 0.5;
        distanceVoltsOffset = 0;
        
        feedbackVoltInterpolant = [];
        feedbackVoltFcn = [];
        
        positionMaxSampleRate = [];
        
        offsetVoltScaling = NaN;
        
        smoothTransitionDuration = 0.005;
        
        lastKnownPositionVoltage = [];
        
        slewRateLimit_V_per_s;
        zeroPositionOnDelete = false;
    end
    
    properties (Dependent)
        lastKnownPosition
    end
    
    properties (Hidden, SetAccess = private)
        positionTask;
        feedbackTask;
        offsetTask;
        
        parkPositionVolts;
    end
    
    properties (Dependent)
        positionAvailable;
        slewRateLimitSet;
        feedbackAvailable;
        offsetAvailable;
        offsetSecondaryTask;
        feedbackCalibrated;
        offsetCalibrated;
        calibrationData;
    end

    methods
        function obj=LinearScanner()
            [~,uuid] = most.util.generateUUIDuint64();
            obj.name = sprintf('Linear Scanner %s',uuid); % ensure unique Task names
        end
        
        function delete(obj)
            try
                if obj.positionAvailable && obj.zeroPositionOnDelete
                    obj.pointPositionVoltage(0);
                end
            catch
            end
            most.idioms.safeDeleteObj(obj.positionTask);
            most.idioms.safeDeleteObj(obj.feedbackTask);
            most.idioms.safeDeleteObj(obj.offsetTask);
        end
    end
    
    %% Setter / Getter methods
    methods
        function set.travelRange(obj,val)
            validateattributes(val,{'numeric'},{'finite','size',[1,2]});
            val = sort(val);
            obj.travelRange = val;
            obj.parkPosition = max(min(obj.parkPosition,obj.travelRange(2)),obj.travelRange(1));
        end
        
        function v = get.travelRange(obj)
            if isempty(obj.travelRange)
                if obj.positionAvailable
                    v = obj.volts2Position(obj.daqOutputRange);
                    v = sort(v);
                else
                    v = [-10 10]; %default
                end
            else
                v = obj.travelRange;
            end
        end
        
        function set.voltsPerDistance(obj,val)
            validateattributes(val,{'numeric'},{'finite','scalar'});
            obj.voltsPerDistance = val;
        end
        
        function set.distanceVoltsOffset(obj,val)
            validateattributes(val,{'numeric'},{'finite','scalar'});
            obj.distanceVoltsOffset = val;
        end
        
        function set.parkPosition(obj,val)
            validateattributes(val,{'numeric'},{'finite','scalar'});
            obj.parkPosition = val;
        end
        
        function set.feedbackVoltInterpolant(obj,val)
            if isa(val,'struct')
                val = structToGriddedInterpolant(val);
            end
            
            if ~isempty(val)
                assert(isa(val,'griddedInterpolant'));
            end
            obj.feedbackVoltInterpolant = val;
        end
        
        function set.offsetVoltScaling(obj,val)
            validateattributes(val,{'numeric'},{'scalar'});
            obj.offsetVoltScaling = val;
        end
        
        function set.positionDeviceName(obj,val)
           if isempty(val)
               val = '';
           else
               validateattributes(val,{'char'},{'row'});
           end
           
           obj.positionDeviceName = val;
           obj.createPositionTask();
        end
        
        function v = get.positionDeviceName(obj)
            if ~isempty(obj.controlDevice)
                v = obj.controlDevice;
            else
                v = obj.positionDeviceName;
            end
        end
        
        function set.positionChannelID(obj,val)
            if isempty(val)
                val = [];
            else
                if ischar(val)
                    val = str2double(val);
                end
                validateattributes(val,{'numeric'},{});
            end
            
            obj.positionChannelID = val;
            obj.createPositionTask();
        end
        
        function set.feedbackDeviceName(obj,val)
            if isempty(val)
                val = '';
            else
                validateattributes(val,{'char'},{'row'});
            end
            
            obj.feedbackDeviceName = val;
            obj.createFeedbackTask();
        end
        
        function v = get.feedbackDeviceName(obj)
            if ~isempty(obj.controlDevice)
                v = obj.controlDevice;
            else
                v = obj.feedbackDeviceName;
            end
        end
        
        function set.feedbackChannelID(obj,val)
            if isempty(val) || isnan(val)
                val = [];
            else
                if ischar(val)
                    val = str2double(val);
                end
                validateattributes(val,{'numeric'},{'scalar'});
            end
            
            obj.feedbackChannelID = val;
            obj.createFeedbackTask();
        end
        
        function set.feedbackTermCfg(obj,val)
            if isempty(val)
                val = 'Differential';
            else
                assert(ismember(val,{'Differential','RSE','NRSE'}),'Invalid terminal configuration ''%s''.',val);
            end
            
            obj.feedbackTermCfg = val;
            obj.createFeedbackTask();
        end
        
        function set.offsetDeviceName(obj,val)
            if isempty(val)
                val = '';
            else
                validateattributes(val,{'char'},{'row'});
            end
            
            obj.offsetDeviceName = val;
            obj.createOffsetTask();
        end
        
        function set.offsetChannelID(obj,val)
            if isempty(val)
                val = [];
            else
                if ischar(val)
                    val = str2double(val);
                end
                validateattributes(val,{'numeric'},{'scalar'});
            end
            
            obj.offsetChannelID = val;
            obj.createOffsetTask();
        end
        
        function val = get.positionAvailable(obj)
            val = ~isempty(obj.positionTask) && isvalid(obj.positionTask);
        end
        
        function val = get.slewRateLimitSet(obj)
            val = ~isinf(obj.slewRateLimit_V_per_s);
        end
        
        function val = get.feedbackAvailable(obj)
            val = ~isempty(obj.feedbackTask) && isvalid(obj.feedbackTask);
        end
        
        function val = get.offsetSecondaryTask(obj)
            val = ~isempty(obj.offsetTask) && isvalid(obj.offsetTask);
        end
        
        function val = get.offsetAvailable(obj)
            val = obj.offsetSecondaryTask || (obj.positionAvailable && obj.positionTask.supportsOffset);
        end
        
        function val = get.feedbackCalibrated(obj)
            val = ~isempty(obj.feedbackVoltInterpolant) || ~isempty(obj.feedbackVoltFcn);
        end
        
        function val = get.offsetCalibrated(obj)
            if obj.offsetSecondaryTask
                val = ~isempty(obj.offsetVoltScaling) && ~isnan(obj.offsetVoltScaling);
            else
                val = obj.offsetAvailable;
            end
        end
        
        function val = get.calibrationData(obj)
            val = struct(...
                 'feedbackVoltInterpolant',griddedInterpolantToStruct(obj.feedbackVoltInterpolant)...
                ,'offsetVoltScaling'      ,obj.offsetVoltScaling...
                );
        end
        
        function set.calibrationData(obj,val)
            assert(isstruct(val));
            props = fieldnames(val);
            
            for idx = 1:length(props)
                prop = props{idx};
                if isprop(obj,prop)
                   obj.(prop) = val.(prop); 
                else
                    most.idioms.warn('%s: Unknown calibration property: %s. You might have to recalibrate the scanner feedback and offset.',obj.name,prop);
                end
            end
        end
        
        function v = get.parkPositionVolts(obj)
            v = obj.position2Volts(obj.parkPosition);
        end
        
        function set.hFpga(obj,v)
            obj.hFpga = v;
            obj.hFpgaDaq = dabs.ni.rio.fpgaDaq.fpgaDaq(v, 'NI7855');
        end
        
        function set.lastKnownPosition(obj,v)
            obj.lastKnownPositionVoltage = obj.position2Volts(v);
        end
        
        function v = get.lastKnownPosition(obj)
            v = obj.volts2Position(obj.lastKnownPositionVoltage);
        end
        
        function set.lastKnownPositionVoltage(obj,v)
            if ~isempty(v)
                validateattributes(v,{'numeric'},{'scalar','finite','nonnan','real'});
            end
            
            obj.lastKnownPositionVoltage = double(v);
        end
        
        function v = get.lastKnownPositionVoltage(obj)
            if obj.positionTask.supportsOutputReadback
                v = obj.positionTask.channelValues;
            else
                v = obj.lastKnownPositionVoltage;
            end
        end
        
        function set.slewRateLimit_V_per_s(obj,v)
            assert(obj.positionAvailable && obj.positionTask.supportsSlewRateLimit, 'This configuration does not support slew rate limit.');
            obj.positionTask.channelSlewRateLimits = v;
        end
        
        function v = get.slewRateLimit_V_per_s(obj)
            if obj.positionAvailable && obj.positionTask.supportsSlewRateLimit
                v = obj.positionTask.channelSlewRateLimits;
            else
                v = inf;
            end
        end
    end
    
    %% Public methods
    methods        
        function val = volts2Position(obj,val)
            if isempty(obj.volt2PositionFcn)
                val = (val - obj.distanceVoltsOffset) ./ obj.voltsPerDistance;
            else
                val = obj.volt2PositionFcn(val);
            end
        end
        
        function val = position2Volts(obj,val)
            if isempty(obj.position2VoltFcn)
                val = val .* obj.voltsPerDistance + obj.distanceVoltsOffset;
            else
                val = obj.position2VoltFcn(val);
            end
            
            % support more than one output channel
            if size(val,2) ~= numel(obj.positionChannelID)
                val = repmat(val,1,numel(obj.positionChannelID));
            end
        end
        
        function val = feedbackVolts2PositionVolts(obj,val)
            if ~isempty(obj.feedbackVoltInterpolant)
                val = obj.feedbackVoltInterpolant(val);
            elseif ~isempty(obj.feedbackVoltFcn)
                val = obj.feedbackVoltFcn(val);
            else
                error('%s: Feedback not calibrated', obj.name);
            end
        end
        
        function unreserveResource(obj)
            obj.positionTask.unreserveResource();
        end
        
        function val = feedbackVolts2Position(obj,val)
            val = obj.feedbackVolts2PositionVolts(val);
            val = obj.volts2Position(val);
        end
        
        function val = position2OffsetVolts(obj,val)
            val = obj.position2Volts(val);
            val = val.* obj.offsetVoltScaling;
        end
        
        function park(obj)
            obj.pointPosition(obj.parkPosition);
        end
        
        function center(obj)
            obj.pointPosition(sum(obj.travelRange)./2);
        end
        
        function pointPosition(obj,position)
            voltage = obj.position2Volts(position);
            obj.pointPositionVoltage(voltage);
        end
        
        function pointPositionVoltage(obj,voltage)
            assert(obj.positionAvailable,'%s: Position output not initialized', obj.name);
            if obj.slewRateLimitSet
                obj.positionTask.setChannelOutputValues(voltage);
            elseif isempty(obj.lastKnownPositionVoltage)
                %warning('Last output voltage for scanner %s is unknown before pointing. Galvo might have tripped.',obj.name);
                obj.positionTask.setChannelOutputValues(voltage);
            else
                obj.smoothTransitionVolts([],voltage);
            end
            
            obj.lastKnownPositionVoltage = voltage;
            
            if obj.offsetAvailable
                obj.pointOffsetPosition(0);
            end
        end
        
        function pointOffsetPosition(obj,position)
            assert(obj.offsetAvailable,'%s: Offset output not initialized', obj.name);
            if obj.offsetSecondaryTask
                volt = obj.position2OffsetVolts(position);
                obj.offsetTask.setChannelOutputValues(volt);
            else
                obj.positionTask.setChannelOutputOffset(position);
            end
        end
        
        function [positionMean, positionSamples] = readFeedbackPosition(obj,n)
            if nargin < 2 || isempty(n)
                n = 100;
            end
            
            assert(obj.feedbackAvailable,'%s: feedback not configured - Cannot read feedback channel.\n',obj.name);
            
            obj.feedbackTask.unreserveResource();
            volt = obj.feedbackTask.readChannelInputValues(n);
            positionSamples = obj.feedbackVolts2Position(volt);
            positionMean = mean(positionSamples);
        end
        
        function calibrate(obj,hWb)
            if nargin<2 || isempty(hWb)
                hWb = [];
            end
            
            if obj.positionAvailable && obj.feedbackAvailable
                fprintf('%s: calibrating feedback',obj.name);
                obj.calibrateFeedback(true,hWb);
                if obj.offsetSecondaryTask
                    fprintf(', offset');
                    obj.calibrateOffset(true,hWb);
                end
                fprintf(' ...done!\n');
            else
                error('%s: feedback not configured - nothing to calibrate\n',obj.name);
            end
        end
        
        function calibrateFeedback(obj,preventTrip,hWb)
            if nargin < 2 || isempty(preventTrip)
                preventTrip = true;
            end
            
            if nargin < 3 || isempty(hWb)
                hWb = [];
            end
            
            if ~isempty(hWb)
                if ~isvalid(hWb)
                    return
                else
                    msg = sprintf('%s: calibrating feedback',obj.name);
                    waitbar(0,hWb,msg);
                end
            end
            
            assert(obj.positionAvailable,'Position output not initialized');
            assert(obj.feedbackAvailable,'Feedback input not initialized');
            
            if obj.offsetAvailable
                obj.pointOffsetPosition(0);
            end
            
            numTestPoints = 10;
            rangeFraction = 0.8;
            
            travelRangeMidPoint = sum(obj.travelRange)/2;
            travelRangeCompressed = diff(obj.travelRange)*rangeFraction;
            
            outputPositions = linspace(travelRangeMidPoint-travelRangeCompressed/2,travelRangeMidPoint+travelRangeCompressed/2,numTestPoints)';
            
            % move to first position
            obj.smoothTransitionPosition([],outputPositions(1));
            if preventTrip && ~obj.positionTask.supportsOutputReadback
                pause(3); % we assume we were at the park position initially, but we cannot know for sure. If galvo trips, wait to make sure they recover
            else
                pause(0.5);
            end
            
            feedbackVolts = zeros(length(outputPositions),1);
            
            cancelled = false;
            for idx = 1:length(outputPositions)
                if idx > 1
                    obj.smoothTransitionPosition(outputPositions(idx-1),outputPositions(idx));
                    pause(0.5); %settle
                end
                averageNSamples = 100;
                samples = obj.feedbackTask.readChannelInputValues(averageNSamples);
                feedbackVolts(idx) = mean(samples);
                
                if ~isempty(hWb)
                    if ~isvalid(hWb)
                        cancelled = true;
                        break
                    else
                        waitbar(idx/length(outputPositions),hWb,msg);
                    end
                end
            end
            
            % park the galvo
            obj.smoothTransitionPosition(outputPositions(end),obj.parkPosition);
            
            if cancelled
                return
            end
            
            [feedbackVolts,sortIdx] = sort(feedbackVolts); % grid vectors of griddedInterpolant have to be strictly monotonic increasing
            outputPositions = outputPositions(sortIdx);
            
            outputVolts = obj.position2Volts(outputPositions);
            
            feedbackVoltInterpolant_old = obj.feedbackVoltInterpolant;
            try
                feedbackVoltInterpolant_new = griddedInterpolant(feedbackVolts,outputVolts,'linear','linear');
            catch ME
                plotCalibrationCurveUnsuccessful();
                rethrow(ME);
            end
            
            obj.feedbackVoltInterpolant = feedbackVoltInterpolant_new;
            obj.feedbackVoltFcn = [];
            
            % validation
            feedbackPosition = obj.feedbackVolts2Position(feedbackVolts(:,1));
            err = outputPositions - feedbackPosition;
            if std(err) < 0.1
                % success
                plotCalibrationCurve();
            else
                % failure
                obj.feedbackVoltInterpolant = feedbackVoltInterpolant_old;
                plotCalibrationCurveUnsuccessful();
                fprintf(2,'Feedback calibration for scanner ''%s'' unsuccessful. SD: %f\n',obj.name,std(err));
            end
            
            %%% local functions
            function plotCalibrationCurve()
                hFig = figure('NumberTitle','off','Name','Scanner Calibration');
                hAx = axes('Parent',hFig,'box','on');
                plot(hAx,obj.feedbackVoltInterpolant.Values,obj.feedbackVoltInterpolant.GridVectors{1},'o-');
                title(hAx,sprintf('%s Feedback calibration',obj.name));
                xlabel(hAx,'Position Output Volt');
                ylabel(hAx,'Position Feedback Volt');
                grid(hAx,'on');
                drawnow();
            end
            
            function plotCalibrationCurveUnsuccessful()
                hFig = figure('NumberTitle','off','Name','Scanner Calibration');
                hAx = axes('Parent',hFig,'box','on');
                plot(hAx,[outputVolts(:,1),feedbackVolts(:,1)],'o-');
                legend(hAx,'Command Voltage','Feedback Voltage');
                title(hAx,sprintf('%s Feedback calibration\nunsuccessful',obj.name));
                xlabel(hAx,'Sample');
                ylabel(hAx,'Voltage');
                grid(hAx,'on');
                drawnow();
            end
        end
        
        function calibrateOffset(obj,preventTrip,hWb)
            if nargin < 2 || isempty(preventTrip)
                preventTrip = true;
            end
            
            if nargin < 3 || isempty(hWb)
                hWb = [];
            end
            
            assert(obj.positionAvailable,'Position output not initialized');
            assert(obj.feedbackAvailable,'Feedback input not initialized');
            assert(obj.offsetAvailable,'Offset output not initialized');
            
            if ~isempty(hWb)
                if ~isvalid(hWb)
                    return
                else
                    msg = sprintf('%s: calibrating offset',obj.name);
                    waitbar(0,hWb,msg);
                end
            end
            
            % center the galvo
            obj.smoothTransitionPosition(obj.parkPosition,0);
            
            numTestPoints = 10;
            rangeFraction = 0.25;
            
            outputPositions = linspace(obj.travelRange(1),obj.travelRange(2),numTestPoints)';
            outputPositions = outputPositions .* rangeFraction;
            
            % move offset to first position
            obj.smoothTransitionPosition(0,outputPositions(1),'offset');
            if preventTrip
                pause(3); % if galvos trip, make sure they recover before continuing
            end
            
            feedbackVolts = zeros(length(outputPositions),1);
            
            cancelled = false;
            for idx = 1:length(outputPositions)
                if idx > 1
                    obj.smoothTransitionPosition(outputPositions(idx-1),outputPositions(idx),'offset');
                    pause(0.5); %settle
                end
                averageNSamples = 100;
                samples = obj.feedbackTask.readChannelInputValues(averageNSamples);
                feedbackVolts(idx) = mean(samples);
                
                if ~isempty(hWb)
                    if ~isvalid(hWb)
                        cancelled = true;
                        break
                    else
                        waitbar(idx/length(outputPositions),hWb,msg);
                    end
                end
            end
            
            % park the galvo
            obj.smoothTransitionPosition(outputPositions(end),0,'offset');
            obj.smoothTransitionPosition(0,obj.parkPosition);
            
            obj.park();
            
            if cancelled
                return
            end
            
            outputVolts = obj.position2Volts(outputPositions);
            outputVolts(:,2) = 1;
            
            feedbackVolts = obj.feedbackVolts2PositionVolts(feedbackVolts); % pre-scale the feedback
            feedbackVolts(:,2) = 1;
            
            offsetTransform = outputVolts' * pinv(feedbackVolts'); % solve in the least square sense
            
            offsetVoltOffset = offsetTransform(1,2);
            assert(offsetVoltOffset < 10e-3,'Offset Calibration failed because Zero Position and Zero Offset are misaligned.');  % this should ALWAYS be in the noise floor
            obj.offsetVoltScaling = offsetTransform(1,1);
        end
        
        function feedback = testWaveformVolts(obj,waveformVolts,sampleRate,preventTrip,startVolts,goToPark,hWb)
            assert(obj.positionAvailable,'Position output not initialized');
            assert(obj.feedbackAvailable,'Feedback input not configured');
            assert(obj.feedbackCalibrated,'Feedback input not calibrated');
            
            if nargin < 4 || isempty(preventTrip)
                preventTrip = true;
            end
            
            if nargin < 5 || isempty(startVolts)
                startVolts = waveformVolts(1);
            end
            
            if nargin < 6 || isempty(goToPark)
                goToPark = true;
            end
            
            if nargin < 7 || isempty(hWb)
                hWb = waitbar(0,'Preparing Waveform and DAQs...','CreateCancelBtn',@(src,evt)delete(ancestor(src,'figure')));
                deletewb = true;
            else
                deletewb = false;
            end
            
            try
                if obj.offsetAvailable
                    obj.pointOffsetPosition(0);
                end
                
                %move to first position
                obj.pointPositionVoltage(startVolts);
                
                if preventTrip && ~obj.positionTask.supportsOutputReadback
                    pause(2); % if galvos trip, ensure we recover before proceeding
                end
                
                obj.positionTask.clearSyncedTasks();
                obj.positionTask.sampleMode = 'finite';
                obj.positionTask.startTrigger = '';
                obj.positionTask.triggerOnStart = true;
                obj.positionTask.allowRetrigger = false;
                obj.positionTask.autoStartStopSyncedTasks = true;
                obj.positionTask.allowEarlyTrigger = false;
                obj.positionTask.sampleRate = sampleRate;
                obj.positionTask.samplesPerTrigger = length(waveformVolts);
                obj.feedbackTask.syncTo(obj.positionTask);
                
                obj.positionTask.writeOutputBuffer(waveformVolts(:));
                obj.positionTask.start();
                
                duration = length(waveformVolts)/sampleRate;
                if duration > .4
                    start = tic();
                    while toc(start) < duration
                        pause(0.1);
                        if ~updateCheckWb(hWb, toc(start)./duration, sprintf('%s: executing waveform test...',obj.name))
                            abort();
                            error('Waveform test cancelled by user');
                        end
                    end
                end
                
                if deletewb
                    most.idioms.safeDeleteObj(hWb);
                end
                
                assert(obj.feedbackTask.waitUntilTaskDone(3), 'Failed to read data.');
                feedbackVolts = obj.feedbackTask.readInputBuffer(length(waveformVolts));
                
                abort();
                
                % might not be accurate if process was aborted early!!
                obj.lastKnownPositionVoltage = waveformVolts(end);
                
                if goToPark
                    % park the galvo
                    obj.pointPositionVoltage(obj.position2Volts(obj.parkPosition));
                end
                
                % scale the feedback
                feedback = obj.feedbackVolts2PositionVolts(feedbackVolts);
            catch ME
                abort();
                obj.park();
                if deletewb
                    most.idioms.safeDeleteObj(hWb);
                end
                rethrow(ME);
            end
            
            function abort()
                obj.feedbackTask.abort();
                obj.positionTask.abort();
                obj.positionTask.clearSyncedTasks();
            end
            
            function continuetf = updateCheckWb(wb,prog,msg)
                if isa(wb,'function_handle')
                    continuetf = wb(prog,msg);
                else
                    continuetf = isvalid(hWb);
                    if continuetf
                        waitbar(toc(start)./duration,hWb,sprintf('%s: executing waveform test...',obj.name));
                    end
                end
            end
        end
        
        function smoothTransitionPosition(obj,old,new,varargin)
            obj.smoothTransitionVolts(obj.position2Volts(old),obj.position2Volts(new),varargin{:});
        end
        
        function smoothTransitionVolts(obj,old,new,type,duration)
            if isempty(old)
                if isempty(obj.lastKnownPositionVoltage)
                    old = obj.parkPositionVolts;
                    warning('Scanner %s attempted a smooth transition, but last position was unknown. Assumed park position.',obj.name);
                else
                    old = obj.lastKnownPositionVoltage;
                end
            end
            
            if nargin < 4 || isempty(type)
                type = 'position';
            end
            
            if nargin < 5 || isempty(duration)
                duration = obj.smoothTransitionDuration;
            end
            
            assert(~isempty(old),'Scanner %s attempted a smooth transition with unknown starting point',obj.name);
            
            numsteps = 100;
            
            switch lower(type)
                case 'position'
                    hTask = obj.positionTask;
                    transitionOffset = false;
                case 'offset'
                    if obj.offsetSecondaryTask
                        hTask = obj.offsetTask;
                        transitionOffset = false;
                    else
                        hTask = obj.positionTask;
                        transitionOffset = true;
                    end
                otherwise
                    error('Unknown task type: %s',type);
            end
            
            assert(~isempty(hTask) && isvalid(hTask));
            
            if transitionOffset
                old = hTask.channelOffsets;
                dvdt = (new-old)/duration;
                
                t = tic;
                for nextUpdate = linspace(duration/numsteps,duration,numsteps)
                    while toc(t) < nextUpdate
                    end
                    hTask.setChannelOutputOffset(old + dvdt*nextUpdate);
                end
            else                
                try
                    aoRate = 20e3;
                    N = round(aoRate*duration);
                    aoData = linspace(old,new,N)';
                    hTask.abort();
                    
                    hTask.sampleRate = aoRate;
                    hTask.sampleMode = 'finite';
                    hTask.samplesPerTrigger = N;
                    hTask.startTrigger = '';
                    hTask.allowRetrigger = false;
                    % Can occasionally calculate values that are
                    % slightly outside range, i.e. 10.000374 etc So we cap
                    % them to range limits
                    aoData((aoData>10)) = 10;
                    aoData((aoData<-10)) = -10;
                    hTask.writeOutputBuffer(aoData);
                    
                    hTask.start()
                    hTask.waitUntilTaskDone(duration+3);
                    hTask.abort();
                    
                    if strcmpi(type,'position')
                        obj.lastKnownPositionVoltage = new;
                    end
                catch ME
                    hTask.abort();
                    rethrow(ME);
                end
            end
        end
    end
    
    methods (Access = private)
        function createPositionTask(obj)
            most.idioms.safeDeleteObj(obj.positionTask);
            obj.positionTask = [];
            
            if isempty(obj.positionDeviceName) || isempty(obj.positionChannelID)
                return;
            end
            
            taskName = sprintf('%s LS Position',obj.name);
            obj.positionTask = dabs.vidrio.ddi.AoTask(obj.positionDeviceName,taskName);
            obj.positionTask.addChannel(obj.positionChannelID, 'Galvo control channel');
            
            obj.positionMaxSampleRate = obj.positionTask.maxSampleRate;
            obj.daqOutputRange = obj.positionTask.channelRanges{1};
        end
        
        function createFeedbackTask(obj)
            most.idioms.safeDeleteObj(obj.feedbackTask);
            obj.feedbackTask = [];
            
            if isempty(obj.feedbackDeviceName) || isempty(obj.feedbackChannelID)
                return;
            end
            
            taskName = sprintf('%s LS Feedback',obj.name);
            obj.feedbackTask = dabs.vidrio.ddi.AiTask(obj.feedbackDeviceName, taskName);
            obj.feedbackTask.addChannel(obj.feedbackChannelID, 'Galvo feedback channel', obj.feedbackTermCfg);
            obj.positionMaxSampleRate = obj.feedbackTask.maxSampleRate;
        end
        
        function createOffsetTask(obj)
            most.idioms.safeDeleteObj(obj.offsetTask);
            obj.offsetTask = [];
            
            if isempty(obj.offsetDeviceName) || isempty(obj.offsetChannelID)
                return
            end
            
            taskName = sprintf('%s LS Offset',obj.name);
            obj.offsetTask = dabs.vidrio.ddi.AoTask(obj.offsetDeviceName,taskName);
            obj.offsetTask.addChannel(obj.offsetChannelID, 'Galvo offset channel');
        end
    end
end


function gistruct = griddedInterpolantToStruct(hGI)
if isempty(hGI)
    gistruct = [];
else
    gistruct = struct();
    gistruct.GridVectors = hGI.GridVectors;
    gistruct.Values = hGI.Values;
    gistruct.Method = hGI.Method;
    gistruct.ExtrapolationMethod = hGI.ExtrapolationMethod;
end
end

function hGI = structToGriddedInterpolant(gistruct)
if isempty(gistruct)
    hGI = [];
else
   hGI = griddedInterpolant (...
       gistruct.GridVectors,...
       gistruct.Values,...
       gistruct.Method,...
       gistruct.ExtrapolationMethod...
       );       
end
end

%--------------------------------------------------------------------------%
% LinearScanner.m                                                          %
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
