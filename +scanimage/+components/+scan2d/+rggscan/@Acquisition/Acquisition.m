classdef Acquisition < scanimage.interfaces.Class
    
    %% FRIEND  PROPS
    %%% Knobs for optional modulation of Acquisition functionality
    properties (Hidden)
        reverseLineRead = false;    % flip the image horizontally
        channelsInvert = false;     % specifies if the digitizer inverts the channel values
        recordFirstSampleDelay = false; % indicates that the last pixel written in a line is the delay from when the line acquisition started to the when the first sample arrived
        
        simulatedFramePeriod = 33;  % Frame Period (in ms) at which to issue frames in simulated mode.
        
        pixelsPerLine = 512;
        linesPerFrame;
        flybackLinesPerFrame;
        totalLinesPerFrame;
        
        roisPerVolume;
        volumesPerAcq;
        stripesPerRoi;
        
        xResolutionNumerator;
		xResolutionDenominator;
		yResolutionNumerator;
		yResolutionDenominator;
        
        simulateFrameData = false;
        roiDataPack = [];
        simNoise = 0;
        simDataSourceFrames;
        simDataSourceRect;
        
        frameAcquiredFcn;
    end
    
    %%% Knobs for testing/debug
    properties (Hidden)
        simulated=false;
        debugOutput = false;        
        dummyData = 0;
        enableBenchmark = false;
        benchmarkData;
        framesProcessed = 0;
    end
    
    %%% Read-only props
    properties (Hidden, SetAccess=private, Dependent)
        adapterModuleChannelCount;
        rawAdcOutput;                % returns up-to-date Adc data without processing. can be queried at any time
    end
        
    %% INTERNAL PROPS
    
    %Immutable props
    properties (Hidden,SetAccess = immutable)
        hScan;
        hFpga;
        hAcqEngine;
        hAcqFifo;
        hAuxFifo;
        hDataScopeFifo;
        
        hTimerContinuousFreqMeasurement;
        
        hLinScanLog; % for arb line scan logging
    end

    properties (Hidden)  
        acqRunning = false;
        acqModeIsLinear = false;
        isLineScan = false;
        is3dLineScan = false;
        
        framesAcquired = 0;                     % total number of frames acquired in the acquisition mode
        acqCounter = 0;                         % number of acqs acquired
        lastEndOfAcquisition = 0;               % total frame number when the last end of acquisition flag was received
        epochAcqMode = [];                      % string, time of the acquisition of the acquisiton of the first pixel in the current acqMode; format: output of datestr(now) '25-Jul-2014 12:55:21'
        
        tagSizePixels = 2;
                
        flagUpdateMask = true;                  % After startup the mask needs to be sent to the FPGA
        
		acqParamBuffer = struct();              % buffer holding frequently used parameters to limit parameter recomputation
        sampleBuffer;
        batchProcessBuffer;
        batchProcessPtr;
        
        externalSampleClock = false;            % indicates if external/internal sample rate is used
        
        stateMachineLoopRate = 0;
        fpgaLoopRate;
        sampleRateAcq = 0;
        rawSampleRateAcq = 0;
        
        fpgaFifoNumberMultiChan;
        fpgaFifoNumberAuxData;
        fpgaSystemTimerLoopCountRegister;
        
        lastLinearStripe;
        loggingStripeBuffer;
        loggingAuxBuffer;
        loggingEnable;               % accessed by MEX function
        stripeCounterFdbk = 0;
        
        hAIFdbk;
        rec3dPath = false;
        zFdbkEn = false;
        zScannerId;
        hZLSC;
    end
    
    properties (Hidden, Dependent)
        scanFrameRate;               % number of frames per second
        dataRate;                    % the theoretical dataRate produced by the acquisition in MB/s
        dcOvervoltage;               % true if input voltage range is exceeded. indicates that coupling changed to AC to protect ADC        
        
        estimatedPeriodClockDelay;   % delays the start of the acquisition relative to the period trigger to compensate for line fillfractionSpatial < 1
        
        channelsActive;              % accessed by MEX function
        channelsDisplay;             % accessed by MEX function
        channelsSave;                % accessed by MEX function
        channelsDisplayArrayPointer; % accessed by MEX function
        channelsSaveArrayPointer;    % accessed by MEX function
        firstSampleDelayEnable;        % accessed by MEX function
    end
    
    %%% Dependent properties computing values needed to pass onto FPGA API
    properties (Hidden, Dependent)
        linePhaseSamples;
        triggerHoldOff;
        beamTiming;        
        
        auxTriggersEnable;          % accessed by MEX
        
        I2CEnable;                  % accessed by MEX
        I2C_STORE_AS_CHAR;          % accessed by MEX
    end    
    
    %%% Properties made available to MEX interface, e.g. for logging and/or frame copy threads
    properties (Hidden, SetAccess = private)
        frameSizePixels;         %Number of Pixels in one frame (not including frame tag)
        dataSizeBytes;            %Number of Bytes in one packed frame (multiple channels)
        packageSizeBytes;         %Number of FIFO elements for one frame (frame + line tags)
        stripeSizeBytes;
        interlacedNumChannels = 4;    %Number of packed channels
        
        fpgaFifoAuxDataActualDepth; %Number of elements the aux trigger can hold. Can differ from FIFO_ELEMENT_SIZE_AUX_TRIGGERS
        mexInst = uint64(0);
    end
    
    %%% Mask params
    properties (Hidden, SetAccess=private)
        mask; %Array specifies samples per pixel for each resonant scanner period
        maskParams; %struct of params pertaining to mask        
    end
    
    properties (Hidden,Dependent)
        fifoSizeFrames;                     %number of frames the DMA FIFO can hold; derived from fifoSizeSeconds
        
        %name constant; accessed by MEX interface
        frameQueueLoggerCapacity;           %number of frames the logging frame queue can hold; derived from frameQueueSizeSeconds
        frameQueueMatlabCapacity;           %number of frames the matlab frame queue can hold; derived from frameQueueLoggerCapacity and framesPerStack
    end

    
    %% CONSTANTS
    properties (Hidden, Constant)
        ADAPTER_MODULE_CHANNEL_COUNT = 4;
        FPGA_RAW_ACQ_LOOP_ITERATIONS_COUNT_FACTOR = 1;
        FPGA_RAW_SAMPLE_RATE_TO_SAMPLE_RATE_FACTOR = 1;
        ADAPTER_MODULE_SAMPLING_RATE_RANGE = [1e6 125e6];
        ADAPTER_MODULE_ADC_BIT_DEPTH = 16;
        ADAPTER_MODULE_AVAIL_INPUT_RANGES = 1;
        
        FRAME_TAG_SIZE_BYTES = 32;
        
        FPGA_SYS_CLOCK_RATE = 200e6;        %Hard coded on FPGA[Hz]
        
        TRIGGER_HEAD_PROPERTIES = {'triggerClockTimeFirst' 'triggerTime' 'triggerFrameStartTime' 'triggerFrameNumber'};
        CHANNELS_INPUT_RANGES = {[-1 1] [-.5 .5] [-.25 .25]};
        
        HW_DETECT_POLLING_INTERVAL = 0.1;   %Hardware detection polling interval time (in seconds)
        HW_DETECT_TIMEOUT = 5;              %Hardware detection timeout (in seconds)
        HW_POLLING_INTERVAL = 0.01;         %Hardware polling interval time (in seconds)
        HW_TIMEOUT = 5;                   %Hardware timeout (in seconds)

        FIFO_SIZE_SECONDS = 1;              %time worth of frame data the DMA Fifo can hold
        FIFO_SIZE_LIMIT_MB = 250;           %limit of DMA FIFO size in MB
        FIFO_ELEMENT_SIZE_BYTES_MULTI_CHAN = 8;  % uint64
        FIFO_ELEMENT_SIZE_BYTES_SINGLE_CHAN = 2; % int16
        PIXEL_SIZE_BYTES = 2;  % int16, also defined in NIFPGAMexTypes.h as pixel_t;
        
        FRAME_QUEUE_LOGGER_SIZE_SECONDS = 1;     %time worth of frame data the logger frame queue can hold
        FRAME_QUEUE_LOGGER_SIZE_LIMIT_MB = 250;  %limit of logger frame queue size in MB
        
        FRAME_QUEUE_MATLAB_SIZE_SECONDS = 1.5;   %time worth of frame data the matlab frame queue can hold
        FRAME_QUEUE_MATLAB_SIZE_LIMIT_MB = 250;  %limit of matlab frame queue size in MB
        
        AUX_DATA_FIFO_SIZE = 20480; % number of bytes for aux data fifo buffer. Each element is 10 bytes, fifo is read once per frame
        AUX_DATA_LOG_ELEMENTS = 1000; % max number of aux data events that can be logged per frame
        
        LOG_TIFF_IMAGE_DESCRIPTION_SIZE = 2000;   % (number of characters) the length of the Tiff Header Image Description
        MEX_SEND_EVENTS = true;
        
        SYNC_DISPLAY_TO_VOLUME_RATE = true; % ensure that all consecutive slices within one volume are transferred from Framecopier. drop volumes instead of frames
    end
    
    %% Lifecycle
    methods
        function obj = Acquisition(hScan,simulated)
            if nargin < 1 || isempty(hScan) || ~isvalid(hScan)
                hScan = [];
            end
            
            if nargin < 2 || isempty(simulated)
                obj.simulated = hScan.simulated;
            else
                obj.simulated = simulated;
            end
            
            obj.hScan = hScan;
            
            obj.dispDbgMsg('Initializing Object & Opening FPGA session');
            
            mdfData = obj.hScan.mdfData;
            obj.hFpga = obj.hScan.hSI.initVdaq(mdfData.acquisitionDeviceId,obj.simulated,mdfData.passiveInit);
            obj.hAcqEngine = obj.hFpga.hAcqEngine(mdfData.acquisitionEngineIdx);
            obj.hAcqFifo = obj.hFpga.fifo_MultiChannelToHostU64(mdfData.acquisitionEngineIdx);
            obj.hAuxFifo = obj.hFpga.fifo_AuxDataToHostU64(mdfData.acquisitionEngineIdx);
            obj.hDataScopeFifo = obj.hFpga.fifo_DataScopeTargetToHost(mdfData.acquisitionEngineIdx);
            
            obj.configureAcqSampleClock();
            
            regs = obj.hFpga.getRegMap();
            obj.fpgaSystemTimerLoopCountRegister = regs.dataRegs.systemClockL.address;
            obj.hTimerContinuousFreqMeasurement = timer('Name','TimerContinuousFreqMeasurement','Period',1,'BusyMode','drop','ExecutionMode','fixedSpacing','TimerFcn',@obj.liveFreqMeasCallback);
            
            %Initialize MEX-layer interface
            AcquisitionMex(obj,'init');
            AcquisitionMex(obj,'registerFrameAcqFcn',@obj.stripeAcquiredCallback);
            
            obj.hLinScanLog = scanimage.components.scan2d.linscan.Logging(obj.hScan);
        end
        
        function delete(obj)
            ME = [];
            try
                if obj.acqRunning
                    obj.abort();
                end
            catch ME
            end
            
            most.idioms.safeDeleteObj(obj.sampleBuffer);
            
            AcquisitionMex(obj,'delete');   % This will now unlock the mex file ot allow us to clear it from Matlab
            clear('AcquisitionMex'); % unload mex file
            
            most.idioms.safeDeleteObj(obj.hTimerContinuousFreqMeasurement);
            most.idioms.safeDeleteObj(obj.hAIFdbk);
            most.idioms.safeDeleteObj(obj.hLinScanLog);
            
            if ~isempty(ME)
                ME.rethrow();
            end
        end
        
        function initialize(obj)
            %Initialize Mask
            obj.computeMask();
        end
    end          
    
    
    %% PROP ACCESS METHODS
    methods
        function set.stateMachineLoopRate(obj,val)
           obj.stateMachineLoopRate = val;
        end
        
        function v = get.fpgaLoopRate(obj)
            v = obj.fpgaLoopRate;
        end
        
        function set.rawSampleRateAcq(obj,val)
            obj.rawSampleRateAcq = val;
            rawSampleRateToSampleRate = obj.FPGA_RAW_SAMPLE_RATE_TO_SAMPLE_RATE_FACTOR;
            
            if ~isempty(rawSampleRateToSampleRate)
                obj.sampleRateAcq = obj.rawSampleRateAcq ./ rawSampleRateToSampleRate;
            else
                obj.sampleRateAcq = obj.rawSampleRateAcq;
            end
            
            obj.stateMachineLoopRate = obj.hFpga.nominalAcqLoopRate;
        end
        
        function val = get.auxTriggersEnable(obj)
            % 5772 does not support aux triggers at this time
           val= obj.hScan.mdfData.auxTriggersEnable;
        end
        
        function val = get.I2CEnable(obj)
            val= obj.hScan.mdfData.i2cEnable;
        end        
        
        function val = get.I2C_STORE_AS_CHAR(obj)
            val = obj.hScan.mdfData.i2cStoreAsChar;
        end
        
        function val = get.dcOvervoltage(~)
            val = false;
        end
        
        function val = get.dataRate(obj)
            val = obj.scanFrameRate * obj.packageSizeBytes;
            val = val / 1E6;   % in MB/s
        end
        
        function val = get.scanFrameRate(obj)
            if obj.hScan.scanModeIsLinear
                val = 1/obj.acqParamBuffer.frameTime;
            else
                val = obj.hScan.scannerFrequency*(2^obj.hScan.bidirectional)/(obj.linesPerFrame+obj.flybackLinesPerFrame);
            end
        end
        
        function val = get.fifoSizeFrames(obj)
            % limit size of DMA Fifo
            fifoSizeSecondsLimit = obj.FIFO_SIZE_LIMIT_MB / obj.dataRate;
            fifoSizeSeconds_ = min(obj.FIFO_SIZE_SECONDS,fifoSizeSecondsLimit);
            
            % hold at least 5 frames            
            val = max(5,ceil(obj.scanFrameRate * fifoSizeSeconds_));
        end
        
        function val = get.frameQueueLoggerCapacity(obj)
            % limit size of frame queue
            frameQueueLoggerSizeSecondsLimit = obj.FRAME_QUEUE_LOGGER_SIZE_LIMIT_MB / obj.dataRate;
            frameQueueLoggerSizeSeconds_ = min(obj.FRAME_QUEUE_LOGGER_SIZE_SECONDS,frameQueueLoggerSizeSecondsLimit);
            
            % hold at least 5 frames
            val = max(5,ceil(obj.scanFrameRate * frameQueueLoggerSizeSeconds_));
        end
        
        function val = get.frameQueueMatlabCapacity(obj)
            % limit size of frame queue
            frameQueueMatlabSizeSecondsLimit = obj.FRAME_QUEUE_MATLAB_SIZE_LIMIT_MB / obj.dataRate;
            frameQueueMatlabSizeSeconds_ = min(obj.FRAME_QUEUE_MATLAB_SIZE_SECONDS,frameQueueMatlabSizeSecondsLimit);
            
            % hold at least 3 frames
            val = max(3,ceil(obj.scanFrameRate * frameQueueMatlabSizeSeconds_));

            if obj.SYNC_DISPLAY_TO_VOLUME_RATE && ~isinf(obj.hScan.framesPerStack)
                max(obj.hScan.framesPerStack,0); %make sure this is positive
                
                % queueSizeInVolumes:
                % has to be at least 1
                % the larger this value the longer the delay between acquisition and display
                % the smaller this value, the more volumes might be dropped
                %   in the display, and the display rate might be reduced
                queueSizeInVolumes = 1.5; % 1.5 means relatively small display latency
                
                assert(queueSizeInVolumes >= 1); % sanity check
                val = max(val,ceil(queueSizeInVolumes * obj.hScan.framesPerStack));
            end
            
            val = val * obj.stripesPerRoi;
        end
        
        function val = get.rawAdcOutput(obj)
            if obj.simulated
                val = [0 0 0 0];
            else
                val = obj.hAcqEngine.acqStatusRawChannelData;
            end
        end

        function val = get.triggerHoldOff(obj)
            val = round(max(0,obj.linePhaseSamples + obj.estimatedPeriodClockDelay));
        end
 
        function val = get.estimatedPeriodClockDelay(obj)
            %TODO: Improve Performance
            totalTicksPerLine = (obj.stateMachineLoopRate / obj.hScan.mdfData.nominalResScanFreq) / 2;
            acqTicksPerLine = totalTicksPerLine * obj.hScan.fillFractionTemporal;
            
            val = round((totalTicksPerLine - acqTicksPerLine)/2);
        end
        
        function val = get.adapterModuleChannelCount(obj)
            val = obj.ADAPTER_MODULE_CHANNEL_COUNT;
        end
        
        function value = get.beamTiming(obj)
            beamClockHoldoff  = -round(obj.hScan.beamClockDelay * obj.stateMachineLoopRate);
            
            durationExt = round(obj.hScan.beamClockExtend * 1e-6 * obj.stateMachineLoopRate);
            beamClockDuration = obj.maskParams.loopTicksPerLine + durationExt;
            
            if (obj.triggerHoldOff + beamClockHoldoff) < 0
                most.idioms.dispError('Beams switch time is set to precede period clock. This setting cannot be fullfilled.\n');
            end
            
            value = [beamClockHoldoff beamClockDuration];
        end
    end
    
    %%% acquisition parameters
    methods
        function val = get.channelsActive(obj)              % accessed by MEX function
            val = obj.hScan.hSI.hChannels.channelsActive;
            % maybe these checks are a little paranoid, but I really don't want
            % the mex function to crash (GJ)
            assert(all(0<val & val<=obj.adapterModuleChannelCount));
            assert(all(floor(val) == val));
            assert(isequal(val,unique(val)));
            assert(issorted(val));
            val = double(val);
        end
        
        function val = get.channelsDisplay(obj)
            val = obj.hScan.hSI.hChannels.channelDisplay;
            % maybe these checks are a little paranoid, but I really don't want
            % the mex function to crash (GJ)
            try
                assert(all(0<val & val<=obj.adapterModuleChannelCount));
                assert(all(floor(val) == val));
                assert(isequal(val,unique(val)));
                assert(issorted(val));
            catch ME
                most.ErrorHandler.logAndReportError(ME);
                rethrow(ME);
            end
            val = double(val);
        end
        
        function val = get.channelsSave(obj)
            val = obj.hScan.hSI.hChannels.channelSave;
            % maybe these checks are a little paranoid, but I really don't want
            % the mex function to crash (GJ)
            try
                assert(all(0<val & val<=obj.adapterModuleChannelCount));
                assert(all(floor(val) == val));
                assert(isequal(val,unique(val)));
                assert(issorted(val));
            catch ME
                most.ErrorHandler.logAndReportError(ME);
                rethrow(ME);
            end
            val = double(val);
        end
        
        function val = get.channelsDisplayArrayPointer(obj)
            val = obj.channelsDisplay;
        end
        
        function val = get.channelsSaveArrayPointer(obj)
            val = obj.channelsSave;
        end
        
        function v = get.firstSampleDelayEnable(obj)
            v = obj.recordFirstSampleDelay && obj.hScan.uniformSampling && (obj.hScan.pixelBinFactor == 1);
        end
    end
    
    %%% live acq params
    methods
        function set.channelsInvert(obj,val)
            validateattributes(val,{'logical','numeric'},{'vector'});
            val = logical(val);
            
            if ~obj.simulated
                if length(val) == 1
                    val = repmat(val,1,obj.adapterModuleChannelCount);
                elseif length(val) < obj.adapterModuleChannelCount
                    val(end+1:end+obj.adapterModuleChannelCount-length(val)) = val(end);
                    most.idioms.warn('ResScan channelsInvert had less entries than physical channels are available. Set to %s',mat2str(val));
                elseif length(val) > obj.adapterModuleChannelCount
                    val = val(1:obj.adapterModuleChannelCount);
                    most.idioms.warn('ResScan channelsInvert had more entries than physical channels are available.');
                end
                
                obj.hAcqEngine.acqParamChannelsInvert = val;
            end
            
            obj.channelsInvert = val;
        end
        
        function val = get.linePhaseSamples(obj)
            val = obj.stateMachineLoopRate * obj.hScan.linePhase;
        end
        
        function set.reverseLineRead(obj,val)
            %validation
            validateattributes(val,{'logical' 'numeric'},{'binary' 'scalar'});
            %set prop
            obj.reverseLineRead = val;
        end
    end
    
    %Property-access helpers
    methods (Hidden)
        function zprpUpdateMask(obj)
            if obj.acqModeIsLinear
                obj.hAcqEngine.acqParamUniformSampling = 1;
                obj.hAcqEngine.acqParamUniformBinSize = obj.hScan.sampleRateDecim;
            elseif obj.hScan.uniformSampling
                obj.hAcqEngine.acqParamUniformSampling = 1;
                obj.hAcqEngine.acqParamUniformBinSize = obj.hScan.pixelBinFactor;
            else
                obj.hAcqEngine.acqParamUniformSampling = 0;
                assert(all(obj.mask > 0),'The horizontal pixel resolution is too high for the acquisition sample rate. Reduce pixels per line or enable uniform sampling.');
                maxNumMaskSamples = 4096; % hard coded array size on FPGA
                N = length(obj.mask);
                assert(N <= maxNumMaskSamples,'Horizontal pixel resolution exceeds maximum of %d',maxNumMaskSamples);

                
                for i = 0:(N-1)
                    obj.hAcqEngine.writeMaskTable(i,obj.mask(i+1));
                end
                
                obj.hAcqEngine.maskTableSize = N-1;
                obj.hAcqEngine.acqParamSamplesPerLine = obj.maskParams.samplesPerLine;
            end
            obj.flagUpdateMask = false;
        end
        
        function zprpUpdateAcqPlan(obj)
            if obj.hScan.hSI.hStackManager.isFastZ
                obj.roisPerVolume = numel(obj.hScan.hSI.hStackManager.zs) + obj.hScan.hSI.hFastZ.numDiscardFlybackFrames;
            else
                obj.roisPerVolume = 1;
            end
            
            if obj.acqModeIsLinear
                obj.hAcqEngine.acqParamLinearMode = 1;
                obj.hAcqEngine.acqParamLinearFramesPerVolume = obj.roisPerVolume;
                
                frameClockTotalTicks = obj.acqParamBuffer.samplesPerFrame * obj.hScan.sampleRateDecim;
                frameHighTicks = obj.acqParamBuffer.endSample * obj.hScan.sampleRateDecim;
                frameLowTicks = frameClockTotalTicks - frameHighTicks;
                
                obj.hAcqEngine.acqParamLinearFrameClkHighTime = frameHighTicks;
                obj.hAcqEngine.acqParamLinearFrameClkLowTime = frameLowTicks;
            else
                obj.hAcqEngine.acqParamLinearMode = 0;
                
                % for now each slice will be an "ROI"
                % in the future ROI info can be properly encoded for proper
                % generation of ROI clock
                addr = 0;
                obj.hAcqEngine.acqPlanNumSteps = obj.roisPerVolume*2;
                halfAcqLines = obj.linesPerFrame / 2;
                
                for i = 1:obj.roisPerVolume
                    if halfAcqLines > 127
                        npHi = floor(halfAcqLines*2^-7);
                        npLo = halfAcqLines - npHi*2^7;
                        
                        obj.hAcqEngine.writeAcqPlan(addr,1,1,npLo);
                        obj.hAcqEngine.writeAcqPlan(addr+1,0,[],npHi);
                        addr = addr + 2;
                    else
                        obj.hAcqEngine.writeAcqPlan(addr,1,1,halfAcqLines);
                        addr = addr + 1;
                    end
                    halfFlybackPeriods = obj.flybackLinesPerFrame / 2;
                    obj.hAcqEngine.writeAcqPlan(addr,1,0,halfFlybackPeriods);
                    addr = addr + 1;
                end
                obj.hAcqEngine.writeAcqPlan(addr,1,0,0);
            end
        end
        
        function zprpResizeAcquisition(obj)
            if obj.simulated
                obj.simulatedFramePeriod = obj.hScan.hSI.hRoiManager.scanFramePeriod*1000;
            else
                %Configure FIFO managed by FPGA interface
                desiredDataFifoSize = obj.packageSizeBytes*obj.fifoSizeFrames;
                desiredAuxFifoSize = obj.AUX_DATA_FIFO_SIZE;
                
                obj.hAcqFifo.configureOrFlush(desiredDataFifoSize);
                obj.hAuxFifo.configureOrFlush(desiredAuxFifoSize);
                
                obj.fpgaFifoNumberMultiChan = obj.hAcqFifo.fifoId;
                obj.fpgaFifoNumberAuxData = obj.hAuxFifo.fifoId;
            end
            
            if obj.acqModeIsLinear
                most.idioms.safeDeleteObj(obj.sampleBuffer);
                obj.sampleBuffer = scanimage.components.scan2d.linscan.SampleBuffer(obj.acqParamBuffer.samplesPerFrame,obj.interlacedNumChannels,'int16');
            end

            obj.reverseLineRead = obj.hScan.mdfData.reverseLineRead;
            obj.enableBenchmark = obj.hScan.enableBenchmark;
            obj.framesProcessed = 0;
            
            if ~obj.isLineScan
                % calculate resolution of first ROI in pix per cm then turn
                % into fraction with 2^30 as the numerator
                
                sf = obj.acqParamBuffer.scanField;
                resDenoms = 2^30 ./ (1e4 * sf.pixelResolutionXY ./ (sf.sizeXY * obj.hScan.hSI.mdfData.objectiveResolution));
                
                obj.xResolutionNumerator = 2^30;
                obj.xResolutionDenominator = resDenoms(1);
                obj.yResolutionNumerator = 2^30;
                obj.yResolutionDenominator = resDenoms(2);
            end
        end
        
        function initI2c(obj)
            obj.hAcqEngine.i2cEnable = obj.hScan.mdfData.i2cEnable;
            if obj.hScan.mdfData.i2cEnable
                % verify valid channel options
                [id, port] = obj.hFpga.dioNameToId(obj.hScan.mdfData.i2cSclPort);
                assert(port ~= (2 + obj.hFpga.isR1), 'Cannot use port %d for i2c clock input.', port);
                obj.hAcqEngine.i2cSclPort = id;
                
                [id, port] = obj.hFpga.dioNameToId(obj.hScan.mdfData.i2cSdaPort);
                if obj.hScan.mdfData.i2cSendAck
                    s = '';
                    if obj.hFpga.isR1
                        s = ' or 1';
                    end
                    assert((port == 'r') || (port < (1+obj.hFpga.isR1)), 'When ack is enabled for i2c interface, data line must be assigned to port 0%s.', s);
                    aeId = obj.hScan.mdfData.acquisitionEngineIdx-1;
                    ackTerm = sprintf('si%d_i2cAck',aeId);
                    obj.hFpga.setDioOutput(obj.hAcqEngine.i2cSdaPort,ackTerm);
                    obj.hAcqEngine.i2cSdaPort = id;
                else
                    assert(port ~= (2 + obj.hFpga.isR1), 'Cannot use port %d for i2c data input.', port);
                    obj.hAcqEngine.i2cSdaPort = id;
                end
            end
            
            obj.hAcqEngine.i2cAddress = obj.hScan.mdfData.i2cAddress;
            obj.hAcqEngine.i2cDebounce = obj.hScan.mdfData.i2cDebounce * obj.stateMachineLoopRate;
        end
    end
    
    
    %% Friendly Methods
    methods (Hidden)
        function loadSimulatedFrames(obj,frames,coords)
            if iscell(frames)
                frames = cat(3,frames{:});
            end
            obj.simDataSourceFrames = int16(frames);
            obj.simDataSourceRect = double(coords);
            AcquisitionMex(obj,'loadSimulatedFrames');
        end
        
        function start(obj)
            obj.dispDbgMsg('Starting Acquisition');
            obj.epochAcqMode = [];
            
            if ~obj.simulated
                obj.verifyRawSampleClockRate();
            end
            
            obj.hAcqEngine.smReset();
            obj.fpgaStartAcquisitionParameters();
            obj.computeMask();
            obj.zprpUpdateMask();
            obj.zprpUpdateAcqPlan();
            obj.hAcqEngine.smReset();
                        
            % reset counters
            obj.framesAcquired = 0;
            obj.acqCounter = 0;
            obj.lastEndOfAcquisition = 0;
            obj.stripeCounterFdbk = 0;
            
            obj.zprpResizeAcquisition();
            obj.initI2c();
            
            if obj.dataRate > 3000
                most.idioms.dispError('The current acquisition data rate is %.2f MB/s, while the bandwith of PCIe 3.0 x4 is 3750MB/s. Approaching this limit might result in data loss.\n',obj.dataRate);
            end
            
            %Configure queue(s) managed by MEX interface
            AcquisitionMex(obj,'resizeAcquisition');

            %Start acquisition
            if ~obj.simulated
                AcquisitionMex(obj,'syncFpgaClock'); % Sync FPGA clock and system clock
            end
            AcquisitionMex(obj,'startAcq');     % Arm Frame Copier to receive frames
            obj.signalReadyReceiveData();
                
            obj.hAcqEngine.smEnable();
            obj.acqRunning = true;
        end
        
        function abort(obj)
            if ~obj.acqRunning
                return
            end
            
            errorMsg = AcquisitionMex(obj,'stopAcq');
            obj.hAcqEngine.smReset();
            
            if ~isempty(errorMsg)
                fprintf(2,'%s\n',errorMsg);
                errordlg(errorMsg);
            end
            
            if ~isempty(obj.hLinScanLog)
                obj.hLinScanLog.abort();
            end
            
            obj.acqRunning = false;
        end
        function stripeData = resonantDataToRois(obj,stripeData,frameData)
            APB = obj.acqParamBuffer;
            
            if isnan(stripeData.zIdx)
                % flyback frame
                stripeData.roiData = {};
            else
                z = APB.zs(stripeData.zIdx);
                stripeData.roiData = {};
                
                if ~isempty(APB.roi)
                    roiData = scanimage.mroi.RoiData();
                    roiData.hRoi = APB.roi;
                    
                    numLines = APB.numLines;
                    startLine = 1;
                    endLine = numLines;
                    roiData.zs = z;
                    roiData.channels = stripeData.channelNumbers;
                    
                    roiData.stripePosition = {[1, numLines]};
                    roiData.stripeFullFrameNumLines = numLines;
                    
                    roiData.acqNumber = stripeData.acqNumber;
                    roiData.frameNumberAcq = stripeData.frameNumberAcq;
                    roiData.frameNumberAcqMode = stripeData.frameNumberAcqMode;
                    roiData.frameTimestamp = stripeData.frameTimestamp;
                    
                    roiData.imageData = cell(length(roiData.channels),1);
                    for chanIdx = 1:length(roiData.channels)
                        if startLine == 1 && endLine == size(frameData{chanIdx},2)
                            % performance improvement for non-mroi mode
                            roiData.imageData{chanIdx}{1} = frameData{chanIdx}; % images are transposed at this point
                        else
                            roiData.imageData{chanIdx}{1} = frameData{chanIdx}(:,startLine:endLine); % images are transposed at this point
                        end
                    end
                    stripeData.roiData{1} = roiData;
                end
            end
        end
        
        function stripeAcquiredCallback(obj)
            if obj.acqModeIsLinear
                if obj.hAcqEngine.acqStatusDataFifoOverflowCount
                    fprintf(2,'Data was lost because frame processing was unable to keep up with acquisition. Aborting acquisition. Try reducing sample rate.\n');
                    errordlg('Data was lost because frame processing was unable to keep up with acquisition. Aborting acquisition. Try reducing sample rate.');
                    obj.hScan.hSI.abort();
                    return
                end
                
                if ~obj.acqRunning
                    return
                end
                
                [rawData, stripeTag, auxData, stripesRemaining, errorMsg] = AcquisitionMex(obj,'getStripe');
                
                if ~isempty(errorMsg)
                    fprintf(2,'%s\n',errorMsg);
                    errordlg(errorMsg);
                    obj.hScan.hSI.abort();
                    return
                end
                
                if isempty(obj.epochAcqMode)
                    obj.epochAcqMode = now;
                end
                
                if (stripesRemaining / obj.acqParamBuffer.frameQueueMatlabCapacity) > .6
                    most.idioms.warn('Frame processing may be too slow to keep up with acquisition.');
                end
                
                % construct stripe data object
                stripeData = scanimage.interfaces.StripeData();
                stripeData.acqNumber = stripeTag.acqNumber;
                stripeData.frameNumberAcqMode = stripeTag.totalAcquiredRois;
                stripeData.frameNumberAcq = (stripeTag.volumeNumberAcq - 1) * obj.roisPerVolume + stripeTag.roiNumber;
                stripeData.stripeNumber = stripeTag.stripeNumber;
                stripeData.stripesRemaining = 0;
                stripeData.totalAcquiredFrames = stripeTag.totalAcquiredRois;
                stripeData.startOfFrame = (stripeTag.stripeNumber == 1);
                stripeData.endOfFrame = stripeTag.stripeNumber == obj.acqParamBuffer.numStripes;
                stripeData.endOfAcquisition = stripeTag.endOfAcq;
                stripeData.endOfAcquisitionMode = stripeTag.endOfAcqMode;
                stripeData.epochAcqMode = obj.epochAcqMode;
                stripeData.overvoltage = false;
                stripeData.channelNumbers = obj.channelsActive(:)';
                
                stripeData.frameTimestamp = stripeTag.frameTimestamp;
                if stripeTag.acqTriggerTimestamp > -1
                    stripeData.acqStartTriggerTimestamp = stripeTag.acqTriggerTimestamp;
                end
                if stripeTag.nextFileMarkerTimestamp > -1
                    stripeData.nextFileMarkerTimestamp = stripeTag.nextFileMarkerTimestamp;
                end
                
                if obj.isLineScan
                else
                    stripeData = obj.hScan.hSI.hStackManager.stripeDataCalcZ(stripeData);
                    stripeData = obj.linearDataToRois(stripeData,rawData);
                    
                    obj.lastLinearStripe = stripeData;
                    
                    if obj.loggingEnable
                        if stripeData.startOfFrame && stripeData.endOfFrame
                            obj.loggingStripeBuffer = stripeData;
                            obj.loggingAuxBuffer = auxData;
                        elseif stripeData.startOfFrame
                            obj.loggingStripeBuffer = copy(stripeData);
                            obj.loggingAuxBuffer = auxData;
                        else
                            obj.loggingStripeBuffer.mergeIn(stripeData);
                            obj.loggingAuxBuffer = [obj.loggingAuxBuffer; auxData];
                        end
                        
                        if stripeData.endOfFrame
                            % consolidate image data into raw data buffer.
                            % concaternate ROIs if there are multiple
                            logImageData = zeros(obj.pixelsPerLine,obj.linesPerFrame,numel(obj.channelsSave),'int16');
                            nd = 0;
                            
                            saveArrayPtr = obj.acqParamBuffer.channelsSaveArrayPointer;
                            for r = 1:numel(obj.loggingStripeBuffer.roiData)
                                roiDims = size(obj.loggingStripeBuffer.roiData{r}.imageData{1}{1});
                                st = nd + 1;
                                nd = st + roiDims(2) - 1;
                                for c = 1:numel(saveArrayPtr)
                                    logImageData(1:roiDims(1),st:nd,c) = obj.loggingStripeBuffer.roiData{r}.imageData{saveArrayPtr(c)}{1};
                                end
                            end
                            
                            errorMsg = AcquisitionMex(obj,'logStripe',obj.loggingStripeBuffer,logImageData,obj.loggingAuxBuffer);
                            
                            if ~isempty(errorMsg)
                                fprintf(2,'Failed to log data: %s\n',errorMsg);
                                errordlg(errorMsg);
                                obj.hScan.hSI.abort();
                                return
                            end
                        end
                    end
                    
                    % display if the frame queue is not getting too full
                    if stripesRemaining < obj.stripesPerRoi
                        obj.frameAcquiredFcn();
                    end
                end
                
                obj.signalReadyReceiveData();
            else
                obj.frameAcquiredFcn();
            end
        end
        
        function stripeData = linearDataToRois(obj,stripeData,ai)   
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
                z = APB.zs(stripeData.zIdx);
                scanFieldParams = APB.scanFieldParams;
                fieldSamples    = [APB.startSample APB.endSample];
                roi             = APB.roi;
                
                if ~isempty(roi)
                    [success,imageDatas,stripePosition] = scannerset.formImage(scanFieldParams,obj.sampleBuffer,fieldSamples,APB.channelsActive,APB.linePhaseSamples,false);
                    
                    if success
                        roiData = scanimage.mroi.RoiData;
                        roiData.hRoi = roi;
                        roiData.zs = z;
                        roiData.stripePosition = {stripePosition};
                        roiData.stripeFullFrameNumLines = scanFieldParams.pixelResolution(2);
                        roiData.frameNumberAcqMode = stripeData.frameNumberAcqMode;
                        roiData.channels = APB.channelsActive;
                        roiData.frameTimestamp = stripeData.frameTimestamp;
                        for iter = 1:length(imageDatas)
                            if APB.numStripes > 1
                                roiData.imageData{iter}{1} = zeros(scanFieldParams.pixelResolution(1),scanFieldParams.pixelResolution(2));
                                roiData.imageData{iter}{1}(:,stripePosition(1):stripePosition(2)) = imageDatas{iter};
                            else
                                roiData.imageData{iter}{1} = imageDatas{iter};
                            end
                        end
                        stripeData.roiData{1} = roiData;
                    end
                end
            end
        end
        function generateSoftwareAcqTrigger(obj)
            if ~obj.simulated
                obj.hAcqEngine.softStartTrig();
            else
                AcquisitionMex(obj,'trigger');
            end
        end
        
        function generateSoftwareAcqStopTrigger(obj)
            obj.hAcqEngine.softStopTrig();
        end
        
        function generateSoftwareNextFileMarkerTrigger(obj)
            obj.hAcqEngine.softNextTrig();
        end
        
        function signalReadyReceiveData(obj)
            AcquisitionMex(obj,'signalReadyReceiveData');
        end
        
        function [success,stripeData] = readStripeData(obj)
            stripeData = [];
            
            if ~obj.acqRunning
                success = false;
                return
            end
            
            if obj.acqModeIsLinear
                stripeData = obj.lastLinearStripe;
%                 obj.lastLinearStripe = [];
                success = ~isempty(stripeData);
            else
                % fetch data from Mex function
                [success, frameData, frameTag, framesRemaining, acqStatus] = AcquisitionMex(obj,'getFrame');
                
                if acqStatus.numDroppedFramesLogger > 0
                    try % this try catch is a bit paranoid, but we want to make sure that the acquisition is aborted and some sort of error is printed
                        errorMsg = sprintf('Data logging lags behind acquisition: %d frames lost.\nAcquisition stopped.\n',acqStatus.numDroppedFramesLogger);
                        most.idioms.dispError(errorMsg);
                    catch ME
                        errorMsg = 'Unknown error.';
                        most.ErrorHandler.logAndReportError(ME);
                    end
                    
                    obj.hScan.hSI.abort();
                    
                    errordlg(errorMsg,'Error during acquisition','modal');
                    success = false;
                    return
                end
                
                if ~success
                    return % read from empty queue
                end
                
                if frameTag.frameTagCorrupt
                    try % this try catch is a bit paranoid, but we want to make sure that the acquisition is aborted and some sort of error is printed
                        pixelDataLost = obj.hAcqEngine.acqStatusDataFifoOverflowCount;
                        auxDataLost = obj.hAcqEngine.acqStatusAuxFifoOverflowCount;
                        
                        fpgaState = obj.hAcqEngine.acqStatusStateMachineState; % we have to capture the fpga state before abort() resets it to idle
                        
                        errorMsg = sprintf(['Error: Data of frame %d appears to be corrupt. Acquistion stopped. ',...
                            'Corrupt data was not logged to disk.\n...',...
                            'Most likely pixels were lost because PXIe data bandwidth was exceeded.\n',...
                            'Debug information: %d, %d overflows; Fpga state = %s\n'],...
                            obj.framesAcquired+1,pixelDataLost,auxDataLost,fpgaState);
                        most.idioms.dispError(errorMsg);
                    catch ME
                        errorMsg = 'Unknown error.';
                        most.ErrorHandler.logAndReportError(ME);
                    end
                    
                    obj.hScan.hSI.abort();
                    
                    errordlg(errorMsg,'Error during acquisition','modal');
                    success = false;
                    return
                end
                
                if frameTag.totalAcquiredFrames == 1
                    obj.epochAcqMode = now;
                end
                
                stripeData = scanimage.interfaces.StripeData();
                stripeData.endOfAcquisitionMode = frameTag.endOfAcqMode;
                stripeData.endOfAcquisition = frameTag.endOfAcq;
                stripeData.overvoltage = frameTag.dcOvervoltage;
                stripeData.startOfFrame = true; % there is only one stripe per frame for resonant scanning
                stripeData.endOfFrame = true;   % there is only one stripe per frame for resonant scanning
                stripeData.stripeNumber = 1;    % there is only one stripe per frame for resonant scanning
                stripeData.frameNumberAcqMode = frameTag.totalAcquiredFrames;
                stripeData.frameNumberAcq = frameTag.totalAcquiredFrames - obj.lastEndOfAcquisition;
                stripeData.stripesRemaining = framesRemaining;
                stripeData.epochAcqMode = obj.epochAcqMode;
                stripeData.channelNumbers = obj.acqParamBuffer.channelDisplay; %This is a little slow, since it's dependent: obj.channelsDisplay;
                
                if obj.simNoise
                    for i = 1:numel(frameData)
                        frameData{i} = frameData{i} + int16(obj.simNoise*rand(size(frameData{i})));
                    end
                end
                
                if obj.enableBenchmark
                    benchmarkDat.totalAcquiredFrames = frameTag.totalAcquiredFrames;
                    
                    benchmarkDat.frameCopierProcessTime = double(typecast(frameTag.nextFileMarkerTimestamp,'uint64'));
                    benchmarkDat.frameCopierCpuCycles = double(frameTag.acqNumber);
                    
                    benchmarkDat.frameLoggerProcessTime = double(typecast(frameTag.acqTriggerTimestamp,'uint64'));
                    benchmarkDat.frameLoggerCpuCycles = double(typecast(frameTag.frameTimestamp,'uint64'));
                    
                    obj.benchmarkData = benchmarkDat;
                    obj.framesProcessed = obj.framesProcessed + 1;
                    
                    stripeData.acqNumber = 1;
                    stripeData.frameTimestamp = 0;
                    stripeData.acqStartTriggerTimestamp = 0;
                    stripeData.nextFileMarkerTimestamp = 0;
                else
                    stripeData.acqNumber = frameTag.acqNumber;
                    stripeData.frameTimestamp = frameTag.frameTimestamp;
                    stripeData.acqStartTriggerTimestamp = frameTag.acqTriggerTimestamp;
                    stripeData.nextFileMarkerTimestamp = frameTag.nextFileMarkerTimestamp;
                end
                
                stripeData = obj.hScan.hSI.hStackManager.stripeDataCalcZ(stripeData);
                stripeData = obj.resonantDataToRois(stripeData,frameData); % images are transposed at this point
                
                % update counters
                if stripeData.endOfAcquisition
                    obj.acqCounter = obj.acqCounter + 1;
                    obj.lastEndOfAcquisition = stripeData.frameNumberAcqMode;
                end
                
                obj.framesAcquired = stripeData.frameNumberAcqMode;
                
                
                % control acquisition
                if stripeData.endOfAcquisitionMode
                    obj.abort(); %self-shutdown
                end
            end
        end
    
        function computeMask(obj)            
            if obj.hScan.uniformSampling
                obj.mask = repmat(obj.hScan.pixelBinFactor,obj.pixelsPerLine,1);
            else
                obj.mask = scanimage.util.computeresscanmask(obj.hScan.scannerFrequency,obj.sampleRateAcq,obj.hScan.fillFractionSpatial, obj.pixelsPerLine);
            end
            
            obj.maskParams.samplesPerLine = sum(obj.mask);
            obj.maskParams.loopTicksPerLine = obj.maskParams.samplesPerLine * round(obj.stateMachineLoopRate / obj.sampleRateAcq);
            obj.flagUpdateMask = true;
        end
        
        function configureAcqSampleClock(obj)
            assert(~obj.acqRunning,'Cannot change sample clock mode during active acquisition');
            
            obj.externalSampleClock = obj.hScan.mdfData.externalSampleClock;
            
            if obj.hScan.mdfData.passiveInit
                if obj.externalSampleClock
                    obj.hFpga.nominalAcqSampleRate = obj.hScan.mdfData.externalSampleClockRate * obj.hScan.mdfData.externalSampleClockMultiplier;
                else
                    obj.hFpga.nominalAcqSampleRate = obj.hFpga.defaultInternalSampleRate;
                end
                obj.rawSampleRateAcq = obj.hFpga.nominalAcqSampleRate;
            elseif obj.hScan.mdfData.externalSampleClock
                try
                    assert(~isempty(obj.hScan.mdfData.externalSampleClockRate),'When external clock is used, rate must be specified.');
                    assert(~isempty(obj.hScan.mdfData.externalSampleClockMultiplier),'When external clock is used, multiplier must be specified.');
                    obj.hFpga.configureExternalSampleClock(obj.hScan.mdfData.externalSampleClockRate, obj.hScan.mdfData.externalSampleClockMultiplier);
                catch
                    most.ErrorHandler.logAndReportError('Failed to configure external sample clock. Check wiring and settings. Defaulting to internal sample clock.');
                    obj.hFpga.configureInternalSampleClock();
                end
            else
                obj.hFpga.configureInternalSampleClock();
            end
            
            obj.rawSampleRateAcq = obj.hFpga.nominalAcqSampleRate;
        end
        
        function verifyRawSampleClockRate(obj)
            assert(obj.hFpga.hClockCfg.checkPll(), 'Digitizer sample clock is not stable. If using external clock verify settings and clock signal.');
            d = abs(obj.hFpga.nominalAcqSampleRate/1e6 - obj.hFpga.sampleClkRate) / obj.hFpga.sampleClkRate;
            assert(d < 0.01, 'Digitizer sample clock is different from expected rate. If using external clock verify settings and clock signal.');
        end
        
        function fpgaUpdateLiveAcquisitionParameters(obj,property)
            if obj.acqRunning || strcmp(property,'forceall')
                obj.dispDbgMsg('Updating FPGA Live Acquisition Parameter: %s',property);
                
                if updateProp('linePhaseSamples')
                    if (obj.linePhaseSamples + obj.estimatedPeriodClockDelay) < 0
                        most.idioms.warn('Phase is too negative. Adjust the physical scan phase on the resonant driver board.');
                    end
                    
                    v =  obj.triggerHoldOff;
                    maxPhase = .4*obj.stateMachineLoopRate/obj.hScan.scannerFrequency;
                    
                    if v > maxPhase
                        most.idioms.warn('Phase is too positive. Adjust the physical scan phase on the resonant driver board.');
                        v = maxPhase;
                    end
                    
                    obj.hAcqEngine.acqParamTriggerHoldoff = uint16(v);
                end
                
                beamTimingH = obj.beamTiming;
                obj.hAcqEngine.acqParamBeamClockAdvance = -beamTimingH(1);
                obj.hAcqEngine.acqParamBeamClockDuration  = beamTimingH(2);
            end
            
            % Helper function to identify which properties to update
            function tf = updateProp(currentprop)
                tf = strcmp(property,'forceall') || strcmp(property,currentprop);
            end
        end
        
        function clearAcqParamBuffer(obj)
            obj.acqParamBuffer = struct();
        end
        
        function updateBufferedPhaseSamples(obj)
            obj.acqParamBuffer.linePhaseSamples = round(obj.hScan.linePhase * obj.hScan.sampleRate); % round to avoid floating point accuracy issue
        end
        
        function [zs, roiGroup, scannerset] = bufferAllSfParams(obj,live)
            if nargin < 2 || isempty(live)
                live = false;
            end
            
            roiGroup = obj.hScan.currentRoiGroup;
            scannerset = obj.hScan.scannerset;
            
            obj.acqModeIsLinear = obj.hScan.scanModeIsLinear;
            
            if obj.isLineScan
                zs = 0;
            else
                % generate slices to scan based on motor position etc
                zs = obj.hScan.hSI.hStackManager.zs;
                obj.acqParamBuffer.zs = zs;
                
                if obj.acqModeIsLinear
                    obj.acqParamBuffer.roi = roiGroup.rois;
                    obj.acqParamBuffer.scanField = roiGroup.rois.scanfields;

                    [lineScanPeriod, lineAcqPeriod] = scannerset.linePeriod(obj.acqParamBuffer.scanField);
                    obj.acqParamBuffer.scanFieldParams =  struct('lineScanSamples',round(lineScanPeriod * obj.hScan.sampleRate),...
                        'lineAcqSamples',round(lineAcqPeriod * obj.hScan.sampleRate),...
                        'pixelResolution',obj.acqParamBuffer.scanField.pixelResolution);
                else
                    obj.acqParamBuffer.roi = roiGroup.rois;
                    obj.acqParamBuffer.numLines = roiGroup.rois.scanfields.pixelResolution(2);
                    obj.acqParamBuffer.scanField = roiGroup.rois.scanfields;
                    obj.acqParamBuffer.scanFields{1}{1} = obj.acqParamBuffer.scanField;
                    
                    if ~live || obj.simulateFrameData
                        obj.acqParamBuffer.framesPerStack = obj.hScan.hSI.hStackManager.numFramesPerVolumeWithFlyback;
                    end
                end
            end
            
        end
        
        function bufferAcqParams(obj,live)
            if nargin < 2 || isempty(live)
                live = false;
            end
            
            if ~live
                obj.acqParamBuffer = struct(); % flush buffer
                
                obj.acqParamBuffer.channelsActive = obj.hScan.hSI.hChannels.channelsActive;
                obj.acqParamBuffer.channelDisplay = obj.hScan.hSI.hChannels.channelDisplay;
                
                obj.acqParamBuffer.channelsSave = obj.hScan.hSI.hChannels.channelSave;
                [~,obj.acqParamBuffer.channelsSaveArrayPointer] = ismember(obj.hScan.hSI.hChannels.channelSave,obj.hScan.hSI.hChannels.channelsActive);
                
                obj.loggingEnable = obj.hScan.hSI.hChannels.loggingEnable;
            end
            
            % generate planes to scan based on motor position etc
            [zs, roiGroup, scannerset] = obj.bufferAllSfParams(live);
            obj.acqParamBuffer.zs = zs;
            
            if obj.isLineScan
            elseif obj.acqModeIsLinear
                % must reflect the size of largest slice for logging (all
                % rois concatenated)
                obj.pixelsPerLine = obj.acqParamBuffer.scanField.pixelResolutionXY(1);
                obj.linesPerFrame = obj.acqParamBuffer.scanField.pixelResolutionXY(2);
                obj.flybackLinesPerFrame = 0;
                obj.totalLinesPerFrame = obj.linesPerFrame;
                
                if ~live
                    fbZs = obj.hScan.hSI.hFastZ.numDiscardFlybackFrames;
                    times = arrayfun(@(z)roiGroup.sliceTime(scannerset,z),zs);
                    obj.acqParamBuffer.frameTime = max(times);
                    obj.acqParamBuffer.samplesPerFrame = round(obj.acqParamBuffer.frameTime * obj.hScan.sampleRate);
                    
                    [obj.acqParamBuffer.startSample,obj.acqParamBuffer.endSample] = roiSamplePositions(roiGroup,scannerset,0);
                    
                    obj.acqParamBuffer.scannerset = scannerset;
                    obj.acqParamBuffer.flybackFramesPerStack = fbZs;
                    obj.acqParamBuffer.numSlices  = numel(zs);
                    obj.acqParamBuffer.roiGroup = roiGroup;
                    
                    obj.updateBufferedPhaseSamples();
                end
                
                obj.frameSizePixels = obj.pixelsPerLine * obj.linesPerFrame;
                obj.dataSizeBytes = obj.PIXEL_SIZE_BYTES .* obj.acqParamBuffer.samplesPerFrame .* obj.interlacedNumChannels;
                obj.packageSizeBytes = obj.PIXEL_SIZE_BYTES .* obj.acqParamBuffer.samplesPerFrame .* obj.interlacedNumChannels;
                
                if obj.hScan.stripingEnable
                    possibleStripes = max(1,floor(obj.acqParamBuffer.frameTime / obj.hScan.stripingPeriod)):-1:1;
                    decims = obj.acqParamBuffer.samplesPerFrame ./ possibleStripes;
                    isValidDecim = ~(decims - round(decims));
                    
                    obj.acqParamBuffer.numStripes = possibleStripes(find(isValidDecim,1));
                    obj.acqParamBuffer.samplesPerStripe = obj.acqParamBuffer.samplesPerFrame / obj.acqParamBuffer.numStripes;
                else
                    obj.acqParamBuffer.numStripes = 1;
                end
                obj.stripeSizeBytes = obj.packageSizeBytes / obj.acqParamBuffer.numStripes;
                obj.stripesPerRoi = obj.acqParamBuffer.numStripes;
                obj.acqParamBuffer.frameQueueMatlabCapacity = obj.frameQueueMatlabCapacity;
                
            elseif ~isempty(obj.acqParamBuffer.scanFields{1})
                obj.pixelsPerLine = obj.acqParamBuffer.scanFields{1}{1}.pixelResolutionXY(1);
                obj.linesPerFrame = obj.acqParamBuffer.numLines;
                
                flybackPeriods = ceil(obj.hScan.flybackTimePerFrame * obj.hScan.scannerFrequency);
                obj.flybackLinesPerFrame = round((flybackPeriods * 2^obj.hScan.bidirectional)/2)*2; % current fpga limitation: linesPerFrame AND flybackLinesPerFrame must be even
                
                obj.totalLinesPerFrame = obj.linesPerFrame + obj.flybackLinesPerFrame;
                
                obj.frameSizePixels = obj.pixelsPerLine * obj.linesPerFrame; %not including frame tag
                obj.dataSizeBytes = obj.PIXEL_SIZE_BYTES * obj.frameSizePixels * obj.interlacedNumChannels;
                obj.packageSizeBytes = (obj.pixelsPerLine + obj.tagSizePixels) * obj.totalLinesPerFrame * obj.interlacedNumChannels * obj.PIXEL_SIZE_BYTES;
                obj.stripesPerRoi = 1;
                obj.stripeSizeBytes = obj.packageSizeBytes;
                
                if obj.simulateFrameData
                    % pack up roi info for mex;
                    Nz = numel(zs);
                    obj.roiDataPack = Nz;
                    for i = 1:Nz
                        sfs = obj.acqParamBuffer.scanFields{i};
                        sls = obj.acqParamBuffer.startLines{i};
                        els = obj.acqParamBuffer.endLines{i};
                        Nsf = numel(sfs);
                        obj.roiDataPack(end+1) = Nsf;
                        for j = 1:Nsf
                            obj.roiDataPack(end+1) = sls(j)-1;
                            obj.roiDataPack(end+1) = els(j)-1;
                            obj.roiDataPack(end+1) = els(j) - sls(j) + 1;
                            
                            sf = sfs{j};
                            r = [sf.centerXY sf.sizeXY] - 0.5*[sf.sizeXY 0 0];
                            obj.roiDataPack(end+1) = r(1);
                            obj.roiDataPack(end+1) = r(2);
                            obj.roiDataPack(end+1) = r(3);
                            obj.roiDataPack(end+1) = r(4);
                        end
                    end
                    
                    if live
                        AcquisitionMex(obj,'updateRois');
                    end
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
                
                startSamples = arrayfun(@(x)(round(x * obj.hScan.sampleRate) + 1), startTimes); % increment because Matlab indexing is 1-based
                endSamples   = arrayfun(@(x)(round(x * obj.hScan.sampleRate)),endTimes );
            end
        end
        
        function resonantScannerFreq = calibrateResonantScannerFreq(obj,averageNumSamples)
            if nargin < 2 || isempty(averageNumSamples)
                averageNumSamples = 100;
            end
            
            if ~obj.simulated
                if ~logical(obj.hAcqEngine.acqStatusPeriodTriggerSettled)
                    resonantScannerFreq = NaN;
                else
%                     t = tic;
%                     nRej = obj.hFpga.AcqStatusPeriodClockRejectedPulses;
                    resonantPeriods = zeros(averageNumSamples,1);
                    resonantPeriods(1) = double(obj.hAcqEngine.acqStatusPeriodTriggerPeriod) / obj.stateMachineLoopRate;
                    for idx = 2:averageNumSamples
                        most.idioms.pauseTight(resonantPeriods(idx-1)*1.1);
                        resonantPeriods(idx) = double(obj.hAcqEngine.acqStatusPeriodTriggerPeriod) / obj.stateMachineLoopRate;
                    end
                    
%                     nRej = obj.hFpga.AcqStatusPeriodClockRejectedPulses - nRej;
%                     dt = toc(t);
%                     rejRate = (double(nRej) / dt);
%                     if rejRate > (obj.hScan.mdfData.nominalResScanFreq * .01)
%                         most.idioms.warn('%d period clock pulses (%d per second) were ignored because they were out of tolerance. Period clock may be noisy.', nRej, floor(rejRate));
%                     end
                    
                    if averageNumSamples > 1
                        meanp = mean(resonantPeriods);
                        stddev = std(resonantPeriods);
                        minp = meanp - 3 * stddev;
                        maxp = meanp + 3 * stddev;
                        resonantPeriodsNrm = resonantPeriods(resonantPeriods > minp);
                        resonantPeriodsNrm = resonantPeriodsNrm(resonantPeriodsNrm < maxp);
                        outliers = numel(find(resonantPeriods < minp)) + numel(find(resonantPeriods > maxp));

                        resonantFrequencies = 1 ./ resonantPeriods;
                        checkMeasurements(resonantFrequencies, outliers);
                        resonantScannerFreq = 1/mean(resonantPeriodsNrm);
                    else
                        resonantScannerFreq = 1/resonantPeriods;
                    end
                end
            else
                resonantScannerFreq = obj.hScan.mdfData.nominalResScanFreq + rand(1);
            end
            
            % nested functions
            function checkMeasurements(measurements, outliers)
                maxResFreqStd = 10;
                maxResFreqError = 0.1;
                
                resFreqMean = mean(measurements);
                resFreqStd  = std(measurements);
                
                resFreqNom = obj.hScan.mdfData.nominalResScanFreq;
                
                if abs((resFreqMean-resFreqNom)/resFreqNom) > maxResFreqError
                    most.idioms.warn('The measured resonant frequency does not match the nominal frequency. Measured: %.1fHz Nominal: %.1fHz',...
                        resFreqMean,resFreqNom) ;
                end
                
                if outliers > 0
                    if outliers > 1
                        s = 's';
                    else
                        s = '';
                    end
                    msg = sprintf('%d outlier%s will be ignored in calculation.\n',outliers,s);
                else
                    msg = '';
                end
                
                if resFreqStd > maxResFreqStd
                    plotMeasurement(measurements);
                    most.idioms.dispError(['The resonant frequency is unstable. Mean: %.1fHz, SD: %.1fHz.\n',...
                               'Possible solutions:\n\t- Reduce the zoom\n\t- increase the value of resonantScannerSettleTime in the Machine Data File\n',...
                               '\t- set hSI.hScanner(''%s'').keepResonantScannerOn = true\n%s'],...
                               resFreqMean,resFreqStd,obj.hScan.name,msg);
                end
            end
           
            function plotMeasurement(measurements)
                persistent hFig
                if isempty(hFig) || ~ishghandle(hFig)
                    hFig = figure('Name','Resonant scanner frequency','NumberTitle','off','MenuBar','none');
                end
                
                clf(hFig);
                figure(hFig); %bring to front
                
                hAx = axes('Parent',hFig);
                plot(hAx,measurements);
                title(hAx,'Resonant scanner frequency');
                xlabel(hAx,'Measurements');
                ylabel(hAx,'Resonant Frequency [Hz]');
            end
        end
        
        function val = setChannelsInputRanges(obj,val)
            val = obj.hFpga.setChannelsInputRanges(val);
        end
        
        function val = setChannelsFilter(obj,val)
            val = obj.hFpga.setChannelsFilter(val);
        end
    end
    
    %% INTERNAL METHODS
    methods (Access = private)        
        function fpgaStartAcquisitionParameters(obj)
            obj.dispDbgMsg('Initializing Acquisition Parameters on FPGA');
            
            %Set basic channel properties
            obj.channelsInvert = obj.hScan.mdfData.channelsInvert;

            if isinf(obj.hScan.framesPerAcq) || (obj.hScan.hSI.hFastZ.enable && isinf(obj.hScan.hSI.hStackManager.actualNumVolumes))
                obj.volumesPerAcq = 0;
            elseif obj.hScan.hSI.hFastZ.enable
                obj.volumesPerAcq = obj.hScan.hSI.hStackManager.numVolumes;
            else
                obj.volumesPerAcq = obj.hScan.framesPerAcq;
            end
            obj.hAcqEngine.acqParamVolumesPerAcq = obj.volumesPerAcq;
            
            if isinf(obj.hScan.trigAcqNumRepeats)
                acquisitionsPerAcquisitionMode_ = 0;
            else
                acquisitionsPerAcquisitionMode_ = obj.hScan.trigAcqNumRepeats;
            end
            
            obj.hAcqEngine.acqParamEnableBidi = obj.hScan.bidirectional;
            obj.hAcqEngine.acqParamTotalAcqs = uint16(acquisitionsPerAcquisitionMode_);
            obj.hAcqEngine.acqParamDummyVal = obj.dummyData;
            obj.hAcqEngine.acqParamPeriodTriggerDebounce = ceil(obj.stateMachineLoopRate * obj.hScan.mdfData.PeriodClockDebounceTime);
            obj.hAcqEngine.acqParamTriggerDebounce = ceil(obj.stateMachineLoopRate * obj.hScan.mdfData.TriggerDebounceTime);
            if numel(obj.hScan.maskDisableDivide) == 1
                obj.hAcqEngine.acqParamDisableDivide = 15 * logical(obj.hScan.maskDisableDivide);
            else
                obj.hAcqEngine.acqParamDisableDivide = bin2dec(fliplr(num2str(logical(obj.hScan.maskDisableDivide))));
            end
            
            % configure aux triggers
            obj.hAcqEngine.acqParamAuxTriggerEnable = obj.auxTriggersEnable;
            if obj.auxTriggersEnable
                obj.hAcqEngine.acqParamAuxTriggerDebounce = floor(obj.hScan.mdfData.auxTriggersTimeDebounce * obj.hFpga.sampleClkRate * 1e6);
                
                auxInputs = obj.hScan.mdfData.auxTriggerInputs;
                tfErrorReported = false;
                for i = 1:4
                    obj.hScan.hTrig.(sprintf('auxTrigger%dIn',i)) = '';
                    if length(auxInputs) >= i
                        try
                            s = auxInputs{i};
                            obj.hScan.hTrig.(sprintf('auxTrigger%dIn',i)) = s;
                        catch ME
                            if ~tfErrorReported
                                most.ErrorHandler.logAndReportError(ME,'Invalid settings for aux trigger recording. ''auxTriggerInputs'' must be a cell array with each entries in the format D#.#');
                            end
                            tfErrorReported = true;
                            obj.hAcqEngine.acqParamAuxTriggerEnable = false;
                        end
                    end
                end
                
                invrt = obj.hScan.mdfData.auxTriggerLinesInvert;
                obj.hAcqEngine.acqParamAuxTriggerInvert = uint8(invrt(1)) + uint8(invrt(2))*2 + uint8(invrt(3))*4 + uint8(invrt(4))*8;
            end
            
            %additionally update the Live Acquisition Parameters
            if ~obj.simulated && ~obj.hScan.scanModeIsLinear
                obj.fpgaUpdateLiveAcquisitionParameters('forceall');
            end
        end
        
        function liveFreqMeasCallback(obj,~,~)
            obj.hScan.liveScannerFreq = obj.calibrateResonantScannerFreq(1);
            obj.hScan.lastLiveScannerFreqMeasTime = clock;
        end
    end
    
    %% Private Methods for Debugging
    methods (Access = private)
        function dispDbgMsg(obj,varargin)
            if obj.debugOutput
                fprintf(horzcat('Class: ',class(obj),': ',varargin{1},'\n'),varargin{2:end});
            end
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
