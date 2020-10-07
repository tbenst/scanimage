classdef Acquisition < scanimage.interfaces.Class
    %% Class specific properties            
    %     properties (Dependent)
    %         channelsInputRanges;                    % [V] 1D cell array of [min max] input ranges for each channel
    %     end
    
    properties
        startTrigIn = '';
        startTrigEdge = 'rising';
        
        disableFpgaAveraging = false;
        disableMatlabAveraging = false;
        
        hFpga;
        fpgaSampleClockMode;
    end
    
    %% Internal properties
    properties (SetAccess = immutable)
        hLinScan;            					% handle of hLinScan
    end
    
    properties (Constant)
        ACQ_BUFFER_SIZE = 30;                   % size of the AI input buffer in stripes
    end
    
    properties (SetAccess = private)
        hAI;                                    % handle of data stream object that abstracts communication between AI Task or FPGA for digitizing light input during scan, e.g. a PMT signal
        hAIFdbk;                                % handle of data stream object that abstracts communication between AI Task or FPGA for digitizing light input during scan, e.g. a PMT signal
        hAIFdbkZ;
        stripeCounterFdbk = 0;                      % total number of stripes acquired
        stripeCounter = 0;                      % total number of stripes acquired
        frameCounter = 0;                       % total number of frames acquired
        everyNSamples;                          % zzSamplesAcquiredFcn is called every N samples
        acqParamBuffer = struct();              % buffer holding frequently used parameters to limit parameter recomputation
        sampleBuffer = scanimage.components.scan2d.linscan.SampleBuffer(); % buffer holding samples for stripes
        acqDevType;
        endOfAcquisition = false;
        useFpgaOffset = false;
        isLineScan = false;
        is3dLineScan = false;
        rec3dPath = false;
        zFdbkShareDaq = false;
        zFdbkEn = false;
        zScannerId;
        hZLSC;
        
        fpgaLoopRate;
    end
    
    properties (Dependent, SetAccess = private)
        active;                                 % (logical) ndicates if the current task is active
    end
    
    %% Lifecycle
    methods
        function obj = Acquisition(hLinScan)
            obj.hLinScan = hLinScan;
            
            obj.ziniPrepareTasks();
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hAI);
            most.idioms.safeDeleteObj(obj.hAIFdbk);
            most.idioms.safeDeleteObj(obj.hAIFdbkZ);
        end
    end
    
    %% Public Methods
    methods
        function start(obj)
            obj.assertNotActive('method:start');
            obj.bufferAcqParams();
            
            % reset counters
            obj.stripeCounterFdbk = 0;
            obj.stripeCounter = 0;
            obj.frameCounter = 0;
            obj.endOfAcquisition = false;
            
            if ~isempty(obj.hFpga) && obj.hLinScan.mdfData.externalSampleClock
                obj.hFpga.measureExternalRawSampleClockRate();
            end
            
            % configure AI task for acquisition
            obj.zzConfigSampModeAndSampPerChan();
            obj.zzConfigInputEveryNAndBuffering();
            obj.sampleBuffer.initialize(obj.acqParamBuffer.samplesPerFrame,obj.hAI.getNumAvailChans,obj.hLinScan.channelsDataType);
            
            
            obj.hAI.start();
        end
        
        function updateBufferedPhaseSamples(obj)
            obj.acqParamBuffer.linePhaseSamples = round(obj.hLinScan.linePhase * obj.hLinScan.sampleRate); % round to avoid floating point accuracy issue
        end
        
        function updateBufferedOffsets(obj)
            if ~isempty(obj.acqParamBuffer)
                if ~obj.useFpgaOffset
                    tmpValA = cast(obj.hLinScan.hSI.hChannels.channelOffset(obj.acqParamBuffer.channelsActive),obj.hLinScan.channelsDataType);
                    tmpValB = cast(obj.hLinScan.hSI.hChannels.channelSubtractOffset(obj.acqParamBuffer.channelsActive),obj.hLinScan.channelsDataType);
                    channelsOffset = tmpValA .* tmpValB;
                    obj.acqParamBuffer.channelsOffset = channelsOffset;
                else
                    N = numel(obj.hLinScan.hSI.hChannels.channelOffset);
                    obj.acqParamBuffer.channelsOffset = zeros(1,numel(obj.acqParamBuffer.channelsActive),obj.hLinScan.channelsDataType);
                    channelsOffset_FPGA = double(obj.hLinScan.hSI.hChannels.channelOffset) .* double(obj.hLinScan.hSI.hChannels.channelSubtractOffset);
                    obj.hFpga.AcqParamLiveChannelOffsets(1:N) = -channelsOffset_FPGA;
                    obj.hFpga.MaskDisableAveraging = repmat(obj.disableFpgaAveraging,size(obj.hFpga.MaskDisableAveraging));
                end
            end
        end
        
        function clearAcqParamBuffer(obj)
            obj.acqParamBuffer = struct();
        end
        
        function zs = bufferAllSfParams(obj)
            roiGroup = obj.hLinScan.currentRoiGroup;
            scannerset=obj.hLinScan.scannerset;
            
            
            if obj.isLineScan
                zs = 0;
            else
                % generate slices to scan based on motor position etc
                zs = obj.hLinScan.hSI.hStackManager.zs;
                obj.acqParamBuffer.zs = zs;
                
                obj.acqParamBuffer.roi = roiGroup.rois;
                obj.acqParamBuffer.scanField = roiGroup.rois.scanfields;
                
                [lineScanPeriod, lineAcqPeriod] = scannerset.linePeriod(obj.acqParamBuffer.scanField);
                obj.acqParamBuffer.scanFieldParams =  struct('lineScanSamples',round(lineScanPeriod * obj.hLinScan.sampleRate),...
                    'lineAcqSamples',round(lineAcqPeriod * obj.hLinScan.sampleRate),...
                    'pixelResolution',obj.acqParamBuffer.scanField.pixelResolution);
            end
        end
        
        function bufferAcqParams(obj,live,keepOld)
            if (nargin < 2 || isempty(live) || ~live) && (nargin < 3 || isempty(keepOld) || ~keepOld)
                obj.acqParamBuffer = struct(); % flush buffer
            end
            
            roiGroup = obj.hLinScan.currentRoiGroup;
            scannerset=obj.hLinScan.scannerset;
            
            if nargin < 2 || isempty(live) || ~live
                lclChannelsActive = obj.hLinScan.hSI.hChannels.channelsActive;
                obj.acqParamBuffer.channelsActive = lclChannelsActive;
                if obj.useFpgaOffset
                    % inversion is handled on FPGA
                    obj.acqParamBuffer.channelsSign = cast(ones(numel(lclChannelsActive),1),obj.hLinScan.channelsDataType);
                    obj.hAI.fpgaInvertChannels = obj.hLinScan.mdfData.channelsInvert;
                else
                    % -1 for obj.mdfData.channelsInvert == true, 1 for obj.mdfDatachannelsInvert == false
                    obj.acqParamBuffer.channelsSign = cast(1 - 2*obj.hLinScan.mdfData.channelsInvert(lclChannelsActive),obj.hLinScan.channelsDataType);
                end
                obj.updateBufferedOffsets();
            end
            
            zs = obj.bufferAllSfParams();
            
            if obj.isLineScan
            else
                if nargin < 2 || isempty(live) || ~live
                    fbZs = obj.hLinScan.hSI.hFastZ.numDiscardFlybackFrames;
                    times = arrayfun(@(z)roiGroup.sliceTime(scannerset,z),zs);
                    obj.acqParamBuffer.frameTime  = max(times);
                    obj.acqParamBuffer.samplesPerFrame = round(obj.acqParamBuffer.frameTime * obj.hLinScan.sampleRate);
                    
                   [obj.acqParamBuffer.startSample,obj.acqParamBuffer.endSample] = roiSamplePositions(roiGroup,scannerset,0);
                    
                    obj.acqParamBuffer.scannerset = scannerset;
                    obj.acqParamBuffer.flybackFramesPerStack = fbZs;
                    obj.acqParamBuffer.numSlices  = numel(zs);
                    obj.acqParamBuffer.roiGroup = roiGroup;
                    
                    obj.updateBufferedPhaseSamples();
                end
            end
            
            function [startSamples, endSamples] = roiSamplePositions(roiGroup,scannerset,z)
                % for each roi at z, determine the start and end time
                transitTimes = reshape(roiGroup.transitTimes(scannerset,z),1,[]); % ensure these are row vectors
                scanTimes    = reshape(roiGroup.scanTimes(scannerset,z),1,[]);
                
                % timeStep = 1/scannerset.sampleRateHz;
                times = reshape([transitTimes;scanTimes],1,[]); % interleave transit Times and scanTimes
                times = cumsum(times);  % cumulative sum of times
                times = reshape(times,2,[]);    % reshape to separate start and stop time vectors
                startTimes = times(1,:);
                endTimes   = times(2,:);
                
                startSamples = arrayfun(@(x)(round(x * obj.hLinScan.sampleRate) + 1), startTimes); % increment because Matlab indexing is 1-based
                endSamples   = arrayfun(@(x)(round(x * obj.hLinScan.sampleRate)),endTimes );
            end
        end
        
        function restart(obj)
            % reset counters
            obj.stripeCounterFdbk = 0;
            obj.stripeCounter = 0;
            obj.frameCounter = 0;
            obj.endOfAcquisition = false;
            
            obj.assertNotActive('method:restart');
            
            
            obj.hAI.start();
        end
        
        function abort(obj,tfUnreserve)
            try
                obj.hAI.abort();
                obj.hAIFdbk.abort();
                obj.hAIFdbkZ.abort();
                
                if tfUnreserve
                    obj.hAI.unreserve();
                    obj.hAIFdbk.control('DAQmx_Val_Task_Unreserve');
                    obj.hAIFdbkZ.control('DAQmx_Val_Task_Unreserve');
                end
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
        end
        
        function data = acquireSamples(obj,numSamples)
            obj.assertNotActive('acquireSamples');
            data = obj.hAI.acquireSamples(numSamples);
                    
            channelsSign = 1 - 2*obj.hLinScan.mdfData.channelsInvert; % -1 for obj.mdfData.channelsInvert == true, 1 for obj.mdfDatachannelsInvert == false
            for chan = 1:size(data,2)
                data(:,chan) = data(:,chan) * channelsSign(chan);     % invert channels
            end
        end
    end
    
    %% Friendly Methods
    methods (Hidden)
        function ziniPrepareFeedbackTasks(obj)
            if ~obj.hLinScan.xGalvo.feedbackAvailable || ~obj.hLinScan.yGalvo.feedbackAvailable
                 return
            end
            
            obj.hAIFdbk.createAIVoltageChan(obj.hLinScan.deviceNameGalvoFeedback,obj.hLinScan.mdfData.XMirrorPosChannelID,'',[],[],[],[],daqMxTermCfgString(obj.hLinScan.mdfData.XMirrorPosTermCfg));
            obj.hAIFdbk.createAIVoltageChan(obj.hLinScan.deviceNameGalvoFeedback,obj.hLinScan.mdfData.YMirrorPosChannelID,'',[],[],[],[],daqMxTermCfgString(obj.hLinScan.mdfData.YMirrorPosTermCfg));
            
            % this is rather intrusive into the internals of fast z so
            % could easily break if that code changes
            obj.zScannerId = obj.hLinScan.hSI.hFastZ.getScannerId(obj.hLinScan.name);
            obj.zFdbkEn = ~isempty(obj.zScannerId);
            if obj.zFdbkEn
                mdfData = obj.hLinScan.hSI.hFastZ.mdfData.actuators(obj.zScannerId);
                obj.zFdbkShareDaq = strcmp(obj.hLinScan.deviceNameGalvoFeedback,mdfData.daqDeviceName);
                
                if obj.zFdbkShareDaq
                    obj.hAIFdbk.createAIVoltageChan(mdfData.daqDeviceName,mdfData.sensorInputChanID);
                else
                    obj.hAIFdbkZ.createAIVoltageChan(mdfData.daqDeviceName,mdfData.sensorInputChanID);
                    obj.hAIFdbkZ.cfgSampClkTiming(obj.hLinScan.sampleRateFdbk, 'DAQmx_Val_FiniteSamps', 2);
                    obj.hAIFdbkZ.cfgDigEdgeStartTrig(obj.hLinScan.hTrig.frameClockTermInt,'DAQmx_Val_Rising');
                    obj.hAIFdbkZ.set('startTrigRetriggerable',1);
                    try
                        obj.hAIFdbkZ.control('DAQmx_Val_Task_Verify');
                        obj.hAIFdbkZ.control('DAQmx_Val_Task_Unreserve');
                    catch
                        obj.zFdbkEn = false;
                    end
                end
            end
            
            obj.hAIFdbk.cfgSampClkTiming(obj.hLinScan.sampleRateFdbk, 'DAQmx_Val_FiniteSamps', 2);
            obj.hAIFdbk.everyNSamplesReadDataEnable = true;
            obj.hAIFdbk.cfgDigEdgeStartTrig('PFI0','DAQmx_Val_Rising');
            obj.hAIFdbk.set('startTrigRetriggerable',1);
            obj.hAIFdbk.everyNSamplesEventCallbacks = @(~,evnt)obj.zzFdbckSamplesAcquiredFcn(evnt.data,evnt.errorMessage);
            
            function cfg = daqMxTermCfgString(str)
                if length(str) > 4
                    str = str(1:4);
                end
                cfg = ['DAQmx_Val_' str];
            end
        end
    end
    
    %% Private Methods
    methods (Access = private)
        function ziniPrepareTasks(obj)
            %Initialize hAI object
            dev = obj.hLinScan.mdfData.deviceNameAcq;
            if obj.hLinScan.isFpgaDaq
                %this is an r-series fpga!
                obj.hAI = scanimage.components.scan2d.linscan.DataStream('rseries', obj.hLinScan.hFpgaDaq);
                obj.hAI.simulated = obj.hLinScan.simulated;
                obj.hAI.nSampleCallback = @(data)obj.zzSamplesAcquiredFcn(data,'');
                obj.hAI.doneCallback = @(data)obj.zzSamplesAcquiredFcn(data,'');
            elseif strncmp(dev, 'RIO', 3) && ~isnan(str2double(dev(4:end)))
                %this is a flexrio fpga!
                obj.useFpgaOffset = true;
                obj.hAI = scanimage.components.scan2d.linscan.DataStream('fpga');
                obj.hAI.simulated = obj.hLinScan.simulated;
                
                if obj.hLinScan.mdfData.secondaryFpgaFifo
                    fifoName = 'fifo_LinScanMultiChannelToHostU64';
                else
                    fifoName = 'fifo_MultiChannelToHostU64';
                end
                
                % Determine bitfile parameters
                fpgaType = obj.hLinScan.mdfData.fpgaModuleType;
                digitizerType = obj.hLinScan.mdfData.digitizerModuleType;
                customSigCondOption = obj.hLinScan.mdfData.customSigCondOption;
                
                if obj.hLinScan.hSI.fpgaMap.isKey(dev)
                    s = obj.hLinScan.hSI.fpgaMap(dev);
                    obj.hFpga = s.hFpga;
                    digitizerType = s.digitizerType;
                else
                    pathToBitfile = [fileparts(which('scanimage')) '\+scanimage\FPGA\FPGA Bitfiles\Microscopy'];
                    
                    if ~isempty(fpgaType)
                        pathToBitfile = [pathToBitfile ' ' fpgaType];
                    end
                    
                    if ~isempty(digitizerType)
                        pathToBitfile = [pathToBitfile ' ' digitizerType];
                    end
                    
                    if ~isempty(customSigCondOption)
                        pathToBitfile = [pathToBitfile ' (' customSigCondOption ')'];
                    end
                    
                    pathToBitfile = [pathToBitfile '.lvbitx'];
                    assert(logical(exist(pathToBitfile, 'file')), 'The FPGA and digitizer combination specified in the machine data file is not currently supported.');
                    
                    if strncmp(fpgaType, 'NI517', 5)
                        dabs.ni.oscope.clearSession;
                        err = dabs.ni.oscope.startSession(dev,pathToBitfile);
                        assert(err == 0, 'Error when attempting to connect to NI 517x device. Code = %d', err);
                        dabs.ni.oscope.configureSampleClock(false,0);
                        digitizerType = 'NI517x';
                    end
                    
                    obj.hFpga = scanimage.fpga.flexRio_SI(pathToBitfile,obj.hLinScan.simulated,digitizerType);
                    
                    if (~obj.hLinScan.simulated)
                        try
                            obj.hFpga.openSession(dev);
                            %Hard-Reset FPGA. This brings the FPGA in a known state after an aborted acquisition
                            obj.hFpga.FpgaResetFcn
                        catch ME
                            error('Scanimage:Acquisition',['Failed to start FPGA. Ensure the FPGA and digitizer module settings in the machine data file match the hardware.\n' ME.message]);
                        end
                    end
                    
                    obj.hLinScan.hSI.fpgaMap(dev) = struct('hFpga',obj.hFpga,'fpgaType',fpgaType,'digitizerType',digitizerType,'bitfilePath',pathToBitfile);
                end
                
                if isempty(customSigCondOption)
                    digitizerTypeWithAppdx = digitizerType;
                else
                    digitizerTypeWithAppdx = [digitizerType ' (' customSigCondOption ')'];
                end
                obj.hAI.setFpgaAndFifo(digitizerType, obj.hFpga.(fifoName), obj.hLinScan.mdfData.secondaryFpgaFifo, digitizerTypeWithAppdx);
                
                obj.hAI.nSampleCallback = @(data)obj.zzSamplesAcquiredFcn(data,'');
                obj.hAI.doneCallback = @(data)obj.zzSamplesAcquiredFcn(data,'');
                obj.hAI.fpgaInvertChannels = obj.hLinScan.mdfData.channelsInvert;
                
                if obj.hLinScan.mdfData.externalSampleClock
                    obj.hFpga.configureAdapterModuleExternalSampleClock(obj.hLinScan.mdfData.externalSampleClockRate);
                    obj.hFpga.measureExternalRawSampleClockRate();
                else
                    obj.hFpga.configureAdapterModuleInternalSampleClock();
                end
                
                obj.hLinScan.laserTriggerFilterSupport = true;
            else
                import dabs.ni.daqmx.*;
                hDev = dabs.ni.daqmx.Device(obj.hLinScan.mdfData.deviceNameAcq);
                obj.acqDevType = hDev.productCategory;
                
                obj.hAI = scanimage.components.scan2d.linscan.DataStream('daq');
                
                obj.hAI.hTask = most.util.safeCreateTask([obj.hLinScan.name '-AnalogInput']);
                obj.hAI.hTaskOnDemand = most.util.safeCreateTask([obj.hLinScan.name '-AnalogInputOnDemand']);
                
                % make sure not more channels are created then there are channels available on the device
                for i=1:obj.hAI.getNumAvailChans(min([obj.hLinScan.MAX_NUM_CHANNELS numel(obj.hLinScan.mdfData.channelIDs)]),obj.hLinScan.mdfData.deviceNameAcq)
                    obj.hAI.hTask.createAIVoltageChan(obj.hLinScan.mdfData.deviceNameAcq,obj.hLinScan.mdfData.channelIDs(i),sprintf('Imaging-%.2d',i-1),-1,1);
                    obj.hAI.hTaskOnDemand.createAIVoltageChan(obj.hLinScan.mdfData.deviceNameAcq,obj.hLinScan.mdfData.channelIDs(i),sprintf('ImagingOnDemand-%.2d',i-1));
                end
                
                % the AI task reuses the sample clock of the AO task this
                % guarantees the two tasks start at the same time and stay in sync
                obj.hAI.hTask.cfgSampClkTiming(obj.hAI.get('sampClkMaxRate'), 'DAQmx_Val_FiniteSamps', 2);
                obj.hAI.hTask.everyNSamplesReadDataEnable = true;
                obj.hAI.hTask.everyNSamplesReadDataTypeOption = 'native';
                obj.hAI.hTask.everyNSamplesEventCallbacks = @(~,evnt)obj.zzSamplesAcquiredFcn(evnt.data,evnt.errorMessage);
                obj.hAI.hTask.doneEventCallbacks = @obj.zzDoneEventFcn;
                
                % the on demand AI task does not use a sample clock
                obj.hAI.hTaskOnDemand.everyNSamplesReadDataTypeOption = 'native';
                obj.hAI.sampClkTimebaseRate = obj.hAI.hTask.get('sampClkTimebaseRate');
            end
            
            obj.hAIFdbk = dabs.ni.rio.fpgaDaq.fpgaDaqAITask.createTaskObj([obj.hLinScan.name '-GalvoFeedbackAI'], obj.hLinScan.hFpgaDaq);
            obj.hAIFdbkZ = most.util.safeCreateTask([obj.hLinScan.name '-ZFeedbackAI']);
        end
        
        function zzDoneEventFcn(obj,~,~)
            % when the event rate is high, for some strange reason the last
            % everyNSamples event of a finite acquisition is not fired, but
            % the doneEvent is fired instead. To work around this issue,
            % register both callbacks. if the done event is fired, generate
            % a 'pseudo callback' for the everyNSamples event
            availableSamples = obj.hAI.hTask.get('readAvailSampPerChan');
            if obj.isLineScan
                data = obj.hAI.hTask.readAnalogData(availableSamples,'native',0);
                obj.zzSamplesAcquiredFcn(data,''); % call the everNSamples callback with the pseudo event data
            elseif mod(availableSamples,obj.everyNSamples) == 0
                stripesAvailable = availableSamples/obj.everyNSamples;
                for idx = 1:stripesAvailable
                    obj.hAI.hTask.isTaskDone;
                    data = obj.hAI.hTask.readAnalogData(obj.everyNSamples,'native',0);
                    obj.zzSamplesAcquiredFcn(data,''); % call the everNSamples callback with the pseudo event data
                end
            else
                % this should never happen. if the done event is fired the
                % input buffer should be either empty, or the last frame
                % (availablesamples == obj.everyNSamples) should be in the
                % buffer
                obj.hLinScan.hSI.abort();
                error('LinScan Acq: Something bad happened: Available number of samples does not match expected number of samples.');
            end
        end
        
        function zzConfigInputEveryNAndBuffering(obj)
            %Determine everyNSamples value
            if obj.isLineScan
            else
                obj.acqParamBuffer.numStripes = determineNumStripes(obj.acqParamBuffer,obj.acqParamBuffer.samplesPerFrame);
                obj.everyNSamples = round(obj.acqParamBuffer.samplesPerFrame / obj.acqParamBuffer.numStripes);
            end
            
            obj.hAI.bufferSize = obj.ACQ_BUFFER_SIZE * obj.everyNSamples;
            obj.hAI.callbackSamples = obj.everyNSamples;
            obj.hAI.configureStream();
            
            function numStripes = determineNumStripes(acqParamBuffer,samplesPerFrame)
                if obj.hLinScan.stripingEnable ...
                        && length(acqParamBuffer.roiGroup.rois) == 1 ...
                        && length(acqParamBuffer.roiGroup.rois(1).scanfields) == 1
                    
                    maxNumStripes = acqParamBuffer.frameTime * obj.hLinScan.mdfData.stripingMaxRate;
                    possibleNumStripes = divisors(samplesPerFrame);
                    possibleNumStripes = possibleNumStripes(possibleNumStripes <= maxNumStripes);
                    numStripes = max(possibleNumStripes);
                    if isempty(numStripes)
                        numStripes = 1;
                    end
                else
                    numStripes = 1;
                end
            end
            
            function d = divisors(n) % local function
                % this algorithm should be sufficiently fast for small values of n
                d = 1:n/2;            % list of possible divisors
                d = d(mod(n,d) == 0); % test all possible divisors
            end
        end
        
        function zzConfigSampModeAndSampPerChan(obj,forceContinuous)
            if nargin < 2 || isempty(forceContinuous)
                forceContinuous = false;
            end
            
            obj.hAI.sampClkRate = obj.hLinScan.sampleRate;
            
            if forceContinuous || obj.hLinScan.framesPerAcq <= 0 || isinf(obj.hLinScan.framesPerAcq) || obj.hLinScan.trigNextStopEnableInternal
                obj.hAI.totalSamples = 0;
            else
                numSamples = obj.acqParamBuffer.samplesPerFrame * obj.hLinScan.framesPerAcq;
                
                if numSamples > 16777213 && strcmpi(obj.acqDevType,'DAQmx_Val_SSeriesDAQ');
                    %limitation in legacy S-Series (e.g. 6110): cannot set
                    %sampQuantSampPerChan to a high value, use continuous
                    %mode instead
                    obj.hAI.totalSamples = 0;
                elseif numSamples >= 2^32
                    obj.hAI.totalSamples = 0;
                else
                    % DAQmx property sampQuantSampPerChan is limited to 2^32-1
                    assert(numSamples < 2^32,['Exceeded maximum number of frames per acquisition.\n' ...
                        'Requested: %d; Maximum possible with current settings: %d (=%d min acquisition time) \n' ...
                        'Workaround: set number of frames to Inf (number of volumes for FastZ acquisition)'],...
                        obj.hLinScan.framesPerAcq,floor((2^32-1)/obj.acqParamBuffer.samplesPerFrame),round((2^32-1)/(60*obj.hLinScan.sampleRate)));
                    
                    obj.hAI.totalSamples = numSamples;
                end
            end
        end
        
        function zzFdbckSamplesAcquiredFcn(obj,data,err)
            if obj.endOfAcquisition
                return
            end
            
            if ~isempty(err)                
                fprintf(2,'Error reading feedback data:\n%s\n',err);
                obj.hLinScan.hSI.abort();
                return;
            end
            
            N = size(data,1);
            finalData = zeros(N,2+obj.rec3dPath,'single');
            
            % convert samples to XY angle
            xyPts = [single(obj.hLinScan.xGalvo.feedbackVolts2Position(single(data(:,1)))) single(obj.hLinScan.yGalvo.feedbackVolts2Position(single(data(:,2))))];
            finalData(:,1:2) = single(scanimage.mroi.util.xformPoints(xyPts,single(obj.hLinScan.scannerToRefTransform)));
            
            if obj.rec3dPath
                if obj.zFdbkShareDaq
                    d = single(data(:,3));
                else
                    d = obj.hAIFdbkZ.readAnalogData(N,[],0);
                end
                finalData(:,3) = single(obj.hZLSC.feedbackVolts2Position(d));
            end
            
            APB = obj.acqParamBuffer;
            if obj.acqParamBuffer.numStripesFdbk > 1
                stripeNumber = mod(obj.stripeCounterFdbk, APB.numStripes) + 1;
                obj.stripeCounterFdbk = obj.stripeCounterFdbk + 1;
                numFrames = 0;
                lastFrameStartIdx = (stripeNumber - 1) * obj.acqParamBuffer.nSampleFdbk + 1;
            else
                numFrames = N / APB.fdbkSamplesPerFrame;
                lastFrameStartIdx = (numFrames - 1) * APB.fdbkSamplesPerFrame + 1;
            end
            
            % pass data to be logged and displayed
            obj.hLinScan.zzFeedbackDataAcquiredCallback(finalData, numFrames, N, lastFrameStartIdx);
        end
        
        function zzSamplesAcquiredFcn(obj,inputSamples,err)
            try
                if obj.endOfAcquisition || ~obj.hLinScan.active
                    return
                end
                
                startProcessingTime = tic;
                
                %             % querrying the fpga takes a millisecond. should poll in C instead
                %             if obj.useFpgaOffset && obj.hFpga.FifoMultiChannelPixelsLost
                %                 fprintf(2,'Pixels lost in transfer from FPGA. Try lowering sample rate.\n');
                %                 obj.hLinScan.hSI.abort();
                %                 return;
                %             end
                
                if ~isempty(err)
                    fprintf(2,'Error reading PMT data:\n%s\n',err);
                    size(inputSamples)
                    obj.hLinScan.hSI.abort();
                    return;
                end
                
                N = size(inputSamples,1);
                if N ~= obj.everyNSamples && ~obj.isLineScan
                    fprintf(2,'Did not receive expected number of samples from analog input task\n');
                    obj.hLinScan.hSI.abort();
                    return;
                end
                
                if obj.isLineScan
                else
                    % calculate local frame and stripe number
                    % this needs to be done before the object counters are updated!
                    frameNumber = obj.frameCounter + 1;
                    stripeNumber = mod(obj.stripeCounter, obj.acqParamBuffer.numStripes) + 1;
                    
                    % update stripe and frame counter
                    obj.stripeCounter = obj.stripeCounter + 1;
                    if ~mod(obj.stripeCounter,obj.acqParamBuffer.numStripes)
                        obj.frameCounter = obj.frameCounter + 1;
                    end
                    
                    if obj.frameCounter >= obj.hLinScan.framesPerAcq && obj.hLinScan.framesPerAcq > 0 && ~obj.hLinScan.trigNextStopEnableInternal
                        obj.endOfAcquisition = true;
                    end
                    
                    % construct stripe data object
                    stripeData = scanimage.interfaces.StripeData();
                    stripeData.frameNumberAcq = frameNumber;
                    stripeData.stripeNumber = stripeNumber;
                    stripeData.stripesRemaining = 0;
                    stripeData.startOfFrame = (stripeNumber == 1);
                    stripeData.endOfFrame = (stripeNumber == obj.acqParamBuffer.numStripes);
                    stripeData.endOfAcquisition = obj.endOfAcquisition;
                    stripeData.overvoltage = false; % TODO: check for overvoltage
                    stripeData.channelNumbers = obj.hLinScan.hSI.hChannels.channelsActive;
                    
                    stripeData = obj.hLinScan.hSI.hStackManager.stripeDataCalcZ(stripeData);
                    stripeData = obj.zzDataToRois(stripeData,inputSamples);
                    % stripe data is still transposed at this point
                    obj.hLinScan.zzStripeAcquiredCallback(stripeData, startProcessingTime);
                end
            catch ME
                most.ErrorHandler.logAndReportError(ME,'Error processing acquisition data.');
            end
        end
        
        function stripeData = zzDataToRois(obj,stripeData,ai)   
            if stripeData.startOfFrame
                obj.sampleBuffer.reset();
            end
            
            obj.sampleBuffer.appendData(ai);
            
            APB = obj.acqParamBuffer;
            
            if isnan(stripeData.zIdx)
                % flyback frame
                stripeData.roiData = {};
            else
                stripeData.roiData = {};

                scannerset = APB.scannerset;
                z = obj.acqParamBuffer.zs(stripeData.zIdx);
                scanFieldParams = APB.scanFieldParams;
                fieldSamples    = [APB.startSample APB.endSample];
                roi             = APB.roi;
                
                if ~isempty(roi)
                    [success,imageDatas,stripePosition] = scannerset.formImage(scanFieldParams,obj.sampleBuffer,fieldSamples,APB.channelsActive,APB.linePhaseSamples,obj.disableMatlabAveraging);
                    
                    if success
                        roiData = scanimage.mroi.RoiData;
                        roiData.hRoi = roi;
                        roiData.zs = z;
                        roiData.stripePosition = {stripePosition};
                        roiData.stripeFullFrameNumLines = scanFieldParams.pixelResolution(2);
                        roiData.channels = APB.channelsActive;
                        for iter = 1:length(imageDatas)
                            image = imageDatas{iter} .* APB.channelsSign(iter) - APB.channelsOffset(iter);
                            
                            if APB.numStripes > 1
                                roiData.imageData{iter}{1} = zeros(scanFieldParams.pixelResolution(1),scanFieldParams.pixelResolution(2));
                                roiData.imageData{iter}{1}(:,stripePosition(1):stripePosition(2)) = image;
                            else
                                roiData.imageData{iter}{1} = image;
                            end
                        end
                        stripeData.roiData{1} = roiData;
                    end
                end
            end
        end
    end
    
    %% Setter/Getter Methods
    methods        
        function val = get.active(obj)
            val = obj.hAI.running;
        end
        
        function set.startTrigIn(obj,val)
            obj.assertNotActive('startTrigIn');
            
            switch obj.startTrigEdge
                case 'rising'
                    edge = 'DAQmx_Val_Rising';
                case 'falling'
                    edge = 'DAQmx_Val_Falling';
                otherwise
                    assert(false);
            end
            
            if isempty(val)
                obj.hAI.disableStartTrig();
            else
                obj.hAI.configureStartTrigger(val,edge);
            end
            
            obj.startTrigIn = val;
        end
        
        function set.startTrigEdge(obj,val)
            obj.assertNotActive('startTrigEdge');
            assert(ismember(val,{'rising','falling'}));
            obj.startTrigEdge = val;
            obj.startTrigIn = obj.startTrigIn;
        end
        
        function v = get.fpgaLoopRate(obj)
            v = obj.hAI.fpgaBaseRate;
        end
    end
    
    %% Helper functions
    methods (Access = private)        
        function assertNotActive(obj,propName)
            assert(~obj.active,'Cannot access property %s during an active acquisition',propName);
        end
        
        function valCoercedWarning(~,propName,requestedVal,actualVal)
            if requestedVal ~= actualVal
                warning('%s was coerced to the nearest possible value. Requested: %d Actual: %d', ...
                    propName, requestedVal, actualVal);
            end
        end
        
        function zprvClearTask(obj, taskPropertyName)
            hTask = obj.(taskPropertyName);
            
            if isempty(hTask) || ~isvalid(hTask)
                return;
            end
            
            hTask.clear();
            obj.(taskPropertyName) = [];
        end
    end
end


%--------------------------------------------------------------------------%
% Acquisition.m                                                            %
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
