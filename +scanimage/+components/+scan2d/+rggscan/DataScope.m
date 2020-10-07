classdef DataScope < scanimage.components.scan2d.interfaces.DataScope
    properties (SetObservable)
        trigger = 'None';
        triggerLineNumber = 1;
        triggerSliceNumber = 1;
        channel = 1;
        acquisitionTime = 0.1;
        triggerHoldOffTime = 0;
        callbackFcn = @(src,evt)plot(evt.data);
    end
    
    properties (SetObservable, SetAccess = protected)
        active = false;
        triggerAvailable = {'none','frame','slice','line'};
    end
    
    properties (Constant, Hidden)
        DATA_SIZE_BYTES = 10;
        FIFO_POLLING_PERIOD = 0.1;
    end
    
    properties (Hidden)
        maxAllowedDataRate = 800e6;
        displayPeriod = 60e-3;
        maxDataLength = 200000;
    end
    
    properties (SetObservable,Dependent,SetAccess = protected)
        channelsAvailable;
        digitizerSampleRate;
        currentDataRate;
    end
    
    properties (Hidden, SetAccess = private)
        hFpga
        hAcqEngine
        hScan2D
        hFifo
        acquisitionActive = false;
        continuousAcqActive = false;
        lastDataReceivedTime = 0;
        hDataStream;
    end
    
    properties (SetAccess = private)
        hFifoPollingTimer;
        hContAcqTimer;
    end
    
    
    %% LifeCycle
    methods
        function obj = DataScope(hScan2D)
            obj.hScan2D = hScan2D;
            obj.hFpga = hScan2D.hAcq.hFpga;
            obj.hAcqEngine = hScan2D.hAcq.hAcqEngine;
            obj.hFifo = hScan2D.hAcq.hDataScopeFifo;
            
            obj.hFifoPollingTimer = timer('Name','DataScope Polling Timer');
            obj.hFifoPollingTimer.ExecutionMode = 'fixedSpacing';
            
            obj.hContAcqTimer = timer('Name','DataScope Continuous Acquisition Timer');
            obj.hContAcqTimer.ExecutionMode = 'fixedSpacing';
            obj.hContAcqTimer.TimerFcn = @obj.nextContAcq;
            obj.hContAcqTimer.Period = 0.03;
        end
        
        function delete(obj)
            obj.abort();
            if ~isempty(obj.hAcqEngine)
                obj.stopFifo();
            end
            most.idioms.safeDeleteObj(obj.hFifoPollingTimer);
            most.idioms.safeDeleteObj(obj.hContAcqTimer);
        end
    end
    
    %% Public Methods
    methods
        function startContinuousAcquisition(obj)
            assert(~obj.active,'DataScope is already started');
            obj.start();
            obj.continuousAcqActive = true;
            obj.lastDataReceivedTime = uint64(0);
            start(obj.hContAcqTimer);
        end
        
        function start(obj)
            assert(~obj.active,'DataScope is already started');
            obj.abort();
            obj.active = true;
            obj.acquisitionActive = false;
            
            % make sure laser trigger port and perdiod clk port are cfgd
            obj.hScan2D.hTrig.applyTriggerConfig();
            
            obj.hAcqEngine.resetDataScope();
            obj.startFifo();
        end
        
        function acquire(obj,callback)
            if nargin < 2 || isempty(callback)
                callback = obj.callbackFcn;
            end
            
            assert(obj.active,'DataScope is not started');
            assert(~obj.acquisitionActive,'Acquisition is already active');
            
            adcRes = obj.hScan2D.channelsAdcResolution;
            inputRange = obj.hScan2D.channelsInputRanges{obj.channel};
            adc2VoltFcn = @(a)inputRange(2)*single(a)./2^(adcRes-1);

            [nSamples,sampleRate,downSampleFactor] = obj.getSampleRate();
            triggerHoldOff = round(obj.triggerHoldOffTime*sampleRate); % coerce triggerHoldOffTime
            triggerHoldOffTime_ = triggerHoldOff/sampleRate;
            
            settings = struct();
            settings.channel = obj.channel;
            settings.sampleRate = sampleRate;
            settings.digitzerSampleRate = obj.digitizerSampleRate;
            settings.downSampleFactor = downSampleFactor;
            settings.inputRange = inputRange;
            settings.adcRes = adcRes;
            settings.nSamples = nSamples;
            settings.trigger = obj.trigger;
            settings.triggerHoldOff = triggerHoldOff;
            settings.triggerHoldOffTime = triggerHoldOffTime_;
            settings.triggerLineNumber = obj.triggerLineNumber;
            settings.triggerSliceNumber = obj.triggerSliceNumber;
            settings.adc2VoltFcn = adc2VoltFcn;
            settings.callback = callback;
            
            obj.configureFpga(settings);
            
            obj.hFifoPollingTimer.Period = obj.FIFO_POLLING_PERIOD;
            obj.hFifoPollingTimer.TimerFcn = @(varargin)obj.checkFifo(nSamples,settings);
            
            obj.lastDataReceivedTime = tic();
            obj.acquisitionActive = true;
            obj.hAcqEngine.startDataScope();
            
            start(obj.hFifoPollingTimer);
        end
        
        function abort(obj)
            try
                if ~isempty(obj.hContAcqTimer)
                    stop(obj.hContAcqTimer);
                end
                if ~isempty(obj.hFifoPollingTimer)
                    stop(obj.hFifoPollingTimer);
                end
                if ~isempty(obj.hAcqEngine)
                    obj.hAcqEngine.resetDataScope();
                end
                obj.active = false;
                obj.acquisitionActive = false;
                obj.continuousAcqActive = false;
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
        end
        
        function info = mouseHoverInfo2Pix(obj,mouseHoverInfo)
            info = [];
            
            if ~isa(obj.hScan2D,'scanimage.components.scan2d.RggScan')
                info = [];
                return
            end
            
            if nargin < 2 || isempty(mouseHoverInfo)
                mouseHoverInfo = obj.hScan2D.hSI.hDisplay.mouseHoverInfo;
            end
            
            acqParamBuffer = obj.hScan2D.hAcq.acqParamBuffer;
            if isempty(acqParamBuffer) || isempty(fieldnames(acqParamBuffer) )|| isempty(mouseHoverInfo)
                return
            end
            
            xPix = mouseHoverInfo.pixel(1);
            yPix = mouseHoverInfo.pixel(2);
            
            [tf,zIdx] = ismember(mouseHoverInfo.z,acqParamBuffer.zs);
            if ~tf
                return
            end
            
            rois = acqParamBuffer.rois{zIdx};
            
            mask = cellfun(@(r)isequal(mouseHoverInfo.hRoi,r),rois);
            if ~any(mask)
                return
            end
            
            roiIdx = find(mask,1);
            roiStartLine = acqParamBuffer.startLines{zIdx}(roiIdx);
            roiEndLine   = acqParamBuffer.endLines{zIdx}(roiIdx);
            
            pixelLine = roiStartLine + yPix - 1;
            
            mask = obj.hScan2D.hAcq.mask;
            if numel(mask) < xPix
                return
            end
            
            cumMask = cumsum(mask);
            
            if xPix==1
                pixelStartSample = 1;
            else
                pixelStartSample = cumMask(xPix-1)+1;
            end
            pixelEndSample = cumMask(xPix);
            
            reverseLine = obj.hScan2D.bidirectional && xor(obj.hScan2D.mdfData.reverseLineRead,~mod(pixelLine,2));
            
            if reverseLine
                pixelStartSample = cumMask(end) - pixelStartSample +1;
                pixelEndSample = cumMask(end) - pixelEndSample + 1;
            end
            
            info = struct();
            info.pixelStartSample = pixelStartSample;
            info.pixelEndSample = pixelEndSample;
            info.pixelStartTime = (pixelStartSample - 1) / obj.digitizerSampleRate;
            info.pixelEndTime = pixelEndSample / obj.digitizerSampleRate;
            info.roiStartLine = roiStartLine;
            info.roiEndLine = roiEndLine;
            info.pixelLine = pixelLine;
            info.lineDuration = (cumMask(end)-1) / obj.digitizerSampleRate;
            info.channel = mouseHoverInfo.channel;
            info.z = mouseHoverInfo.z;
            info.zIdx = zIdx;
        end
    end
    
    %% Internal Functions    
    methods (Hidden)
        function nextContAcq(obj,varargin)
            if ~obj.continuousAcqActive || obj.acquisitionActive 
                return
            end
            
            elapsedTime = toc(obj.lastDataReceivedTime);
            
            if elapsedTime >= obj.displayPeriod
                obj.acquire();
            end
        end
        
        function restart(obj)
            if obj.continuousAcqActive
                obj.abort();
                obj.startContinuousAcquisition();
            elseif obj.active
                obj.abort();
                obj.start();
            end
        end
        
        function configureFpga(obj,settings)            
            obj.hAcqEngine.scopeParamDecimationLB2 = log2(settings.downSampleFactor);
            obj.hAcqEngine.scopeParamNumberOfSamples = settings.nSamples;
            obj.hAcqEngine.scopeParamTriggerHoldoff = settings.triggerHoldOff;
                        
            switch lower(settings.trigger)
                case {'none' ''}
                    obj.hAcqEngine.scopeParamTriggerId = 0;
                case 'frame'
                    obj.hAcqEngine.scopeParamTriggerId = 12;
                    % set slice number to any slide
                case 'slice'
                    obj.hAcqEngine.scopeParamTriggerId = 12;
                    % set slice number
                case 'line'
                    obj.hAcqEngine.scopeParamTriggerId = 'Line';
                    % set line number
                otherwise
                    error('Unsupported trigger type: %s',settings.trigger);
            end
        end        
        
        function startFifo(obj)
            if obj.hFifo.hostBufferSize < obj.maxDataLength*obj.DATA_SIZE_BYTES
                obj.hFifo.configure(obj.maxDataLength*obj.DATA_SIZE_BYTES);
            else
                obj.hFifo.flush();
            end
        end
        
        function stopFifo(obj)
            obj.hFifo.close();
        end
        
        function checkFifo(obj,nSamples,settings)
            if ~obj.acquisitionActive
                return
            end
            
            try
                assert(~obj.hAcqEngine.scopeStatusFifoOverflowCount,'Data Scope data was lost. PCIe bandwidth may have been exceeded.');
            catch ME
                try
                    obj.abort();
                catch
                end
                most.ErrorHandler.logAndReportError(ME);
                return;
            end
            
            [fifoData,elremaining] = obj.hFifo.read(nSamples*obj.DATA_SIZE_BYTES,'int16');
            
            if isempty(fifoData)
                return
            end
            
            stop(obj.hFifoPollingTimer);
            
            if elremaining
                obj.abort();
                error('DataScope: No elements are supposed to remain in FIFO');
            end

            channeldata = fifoData(settings.channel:5:end);
            triggers = typecast(fifoData(5:5:end),'uint16');
            triggers = triggerDecode(triggers);
            
            if ~isempty(settings.callback)
                src = obj;
                evt = struct();
                evt.data = channeldata;
                evt.triggers = triggers;
                evt.settings = settings;
                settings.callback(src,evt);
            end
            
            obj.acquisitionActive = false;
            
            function s = triggerDecode(trigger)
                s = struct();
                s.PeriodClockRaw        = bitget(trigger,1);
                s.PeriodClockDebounced  = bitget(trigger,2);
                s.PeriodClockDelayed    = bitget(trigger,3);
                s.MidPeriodClockDelayed = bitget(trigger,4);
                s.AcquisitionTrigger    = bitget(trigger,5);
                s.AdvanceTrigger        = bitget(trigger,6);
                s.StopTrigger           = bitget(trigger,7);
                s.LaserTriggerRaw       = bitget(trigger,15);
                s.LaserTrigger          = bitget(trigger,14);
                s.ControlSampleClock    = bitget(trigger,16);
                s.FrameClock            = bitget(trigger,12);
                s.BeamClock             = bitget(trigger,10);
                s.AcquisitionActive     = bitget(trigger,8);
                s.VolumeTrigger         = bitget(trigger,13);
                s.LineActive            = bitget(trigger,9);
            end
        end
        
        function [nSamples,sampleRate,downSampleFactor] = getSampleRate(obj)
            nSamples = ceil(obj.acquisitionTime * obj.digitizerSampleRate);
            if nSamples <= obj.maxDataLength
                % entire acquisition fits into FPGA FIFO
                sampleRate = obj.digitizerSampleRate;
                downSampleFactor = 1;
            else
                % need to coerce to maxAllowedDataRate, not exceeding
                % maxDataLength
                maxAllowedSampleRate = obj.maxAllowedDataRate / obj.DATA_SIZE_BYTES;
                maxAllowedSampleRate = min(obj.digitizerSampleRate,maxAllowedSampleRate);
                % coerce maxAllowedSampleRate
                downSampleFactor = 2^ceil(log2(obj.digitizerSampleRate/maxAllowedSampleRate));
                sampleRate = obj.digitizerSampleRate / downSampleFactor;
                nSamples = ceil(sampleRate * obj.acquisitionTime);
                
                if nSamples > obj.maxDataLength
                    factor = nSamples / obj.maxDataLength;
                    downSampleFactor = downSampleFactor * factor;
                    downSampleFactor = min(2^ceil(log2(downSampleFactor)),64);
                    sampleRate = obj.digitizerSampleRate / downSampleFactor;
                    nSamples = min(ceil(sampleRate * obj.acquisitionTime),obj.maxDataLength);
                end
            end
        end
    end
    
    %% Property Setter/Getter
    methods
        function val = get.digitizerSampleRate(obj)
            val = obj.hFpga.sampleClkRate * 1e6;
        end
        
        function val = get.channelsAvailable(obj)
            val = obj.hScan2D.channelsAvailable;
        end
        
        function set.channel(obj,val)
            validateattributes(val,{'numeric'},{'integer','positive','<=',obj.channelsAvailable});
            obj.channel = val;
        end
        
        function set.maxDataLength(obj,val)
            assert(~obj.active,'Cannot change maxDataLength while DataScope is active');
            obj.maxDataLength = val;
        end
                
        function set.trigger(obj,val)
            val = lower(val);
            mask = strcmpi(val,obj.triggerAvailable);
            assert(sum(mask) == 1,'%s is not a supported Trigger Type',val);
            obj.trigger = val;
            
            obj.restart(); % abort old acquisition that might be stuck on a trigger that's not firing
        end
        
        function set.triggerLineNumber(obj,val)
            validateattributes(val,{'numeric'},{'scalar','nonnegative','integer','<',2^16});
            obj.triggerLineNumber = val;
            
            obj.restart(); % abort old acquisition that might be stuck on a trigger that's not firing
        end
        
        function set.triggerSliceNumber(obj,val)
            validateattributes(val,{'numeric'},{'scalar','nonnegative','integer','<',2^16});
            obj.triggerSliceNumber = val;
            
            obj.restart(); % abort old acquisition that might be stuck on a trigger that's not firing
        end
        
        function val = get.currentDataRate(obj)
            [nSamples,sampleRate,downSampleFactor] = obj.getSampleRate();
            val = sampleRate * obj.DATA_SIZE_BYTES;
        end
    end
end



%--------------------------------------------------------------------------%
% DataScope.m                                                              %
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
