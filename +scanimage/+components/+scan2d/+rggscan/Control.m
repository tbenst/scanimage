classdef Control < scanimage.interfaces.Class    
    properties (Hidden, SetAccess = immutable)
        hScan;
        hFpga;
        hAcqEngine;
        simulated=false;
    end
    
    % Live Values - these properties can be updated during an active acquisition
    properties (Dependent)
        galvoParkVoltsX;        
        galvoParkVoltsY;
    end
    
    % Internal Parameters
    properties (SetAccess = private, Hidden)
        xGalvoExists = false;
        resonantMirrorExists = false;
        
        hAOTaskResonantScannerZoom;
        hDOTaskResonantScannerEnable;
        hAOTaskGalvo;
        hAOTaskBeams;
        hAOTaskZ;
        
        acquisitionActive = false;
        resScanBoxCtrlInitialized;
        
        resonantScannerLastUpdate = clock;
        resonantScannerLastWrittenValue;
        
        activeFlag = false;
        
        galvoBufferLength = [];
        beamBufferLength = [];
        zBufferLength = [];
    end
    
    properties (Hidden)
        useScannerSampleClk = true;
        scannerSampsPerPeriod;
        waveformLenthPeriods;
        waveformResampLength;
    end
    
    %% Lifecycle
    methods
        function obj = Control(hScan,simulated)
            if nargin < 1 || isempty(hScan)
                hScan = [];
            end
            
            if nargin < 2 || isempty(simulated)
                obj.simulated=false;
            else
                obj.simulated=simulated;
            end
            
            obj.hScan = hScan;
            obj.hFpga = hScan.hAcq.hFpga;
            obj.hAcqEngine = hScan.hAcq.hAcqEngine;
            
            %Get property values from machineDataFile
            obj.resonantMirrorExists = ~isempty(obj.hScan.mdfData.resonantAngularRange);
            obj.xGalvoExists = ~isempty(obj.hScan.mdfData.galvoAOChanIDX);
        end
        
        function delete(obj)
            try
                if obj.acquisitionActive
                    obj.stop();
                end
                
                % disable resonant scanner (may still be on depending on setting)
                obj.resonantScannerActivate(false);
                
                deleteTasks();                
            catch ME
                deleteTasks();
                rethrow(ME);
            end
            
            function deleteTasks()
                most.idioms.safeDeleteObj(obj.hAOTaskGalvo);
                most.idioms.safeDeleteObj(obj.hAOTaskBeams);
                most.idioms.safeDeleteObj(obj.hAOTaskZ);
                most.idioms.safeDeleteObj(obj.hAOTaskResonantScannerZoom);
                most.idioms.safeDeleteObj(obj.hDOTaskResonantScannerEnable);
            end
        end
        
        function initialize(obj)
            obj.initializeTasks();
        end
    end
    
    %% Public Methods
    methods        
        function start(obj)
            assert(~obj.acquisitionActive,'Acquisition is already active');
            % Reconfigure the Tasks for the selected acquisition Model
            obj.setupSampleClk();
            obj.updateTaskCfg();
            % this pause needed for the Resonant Scanner to reach
            % its amplitude and send valid triggers
            obj.activeFlag = true;
            obj.resonantScannerWaitSettle();
            % during resonantScannerWaitSettle a user might have clicked
            % 'abort' - which in turn calls obj.abort and unreserves
            % obj.hAOTaskGalvo; catch this by checking obj.activeflag
            if ~obj.activeFlag
                errorStruct.message = 'Soft error: ResScan was aborted before the resonant scanner could settle.';
                errorStruct.identifier = '';
                errorStruct.stack = struct('file',cell(0,1),'name',cell(0,1),'line',cell(0,1));
                error(errorStruct); % this needs to be an error, so that Scan2D will be aborted correctly
            end
            
            if ~obj.simulated
                obj.hAOTaskGalvo.start();
                
                if ~isempty(obj.hAOTaskBeams.channels)
                    obj.hAOTaskBeams.start();
                end
                
                if ~isempty(obj.hAOTaskZ.channels) && obj.hScan.hSI.hFastZ.outputActive
                    obj.hAOTaskZ.start();
                end
                
                obj.hScan.liveScannerFreq = [];
                obj.hScan.lastLiveScannerFreqMeasTime = [];
            end
            
            obj.acquisitionActive = true;  
        end
        
        function stop(obj,soft)
            if nargin < 2 || isempty(soft)
                soft = false;
            end
            
            obj.hAOTaskGalvo.stop();
            obj.hAOTaskBeams.stop();
            obj.hAOTaskZ.stop();
            
            obj.activeFlag = false;
                        
            %Park scanner
            % parkGalvo() has to be called after acquisitionActive is set to
            % false, otherwise we run into an infinite loop
            obj.acquisitionActive = false;
            if ~obj.simulated
                obj.parkGalvo();
            end
            
            obj.resonantScannerActivate(obj.hScan.scanModeIsResonant && (obj.hScan.keepResonantScannerOn || soft));
        end
        
        function resonantScannerActivate(obj,activate,volts)
           if nargin < 2 || isempty(activate)
               activate = true;
           end
           
           if activate
               if nargin < 3 || isempty(volts)
                   resScanOutputPoint = obj.nextResonantVoltage();
               else
                   resScanOutputPoint = volts;
               end
           else
               resScanOutputPoint = 0;
           end
           
           obj.resonantScannerUpdateOutputVolts(resScanOutputPoint);
        end
        
        function resonantScannerWaitSettle(obj,settleTime)
            if nargin < 2 || isempty(settleTime)
            	timeToWait = obj.getRemainingResSettlingTime();
			else
            	timeToWait = obj.getRemainingResSettlingTime(settleTime);
            end
            
            if obj.resonantMirrorExists && (timeToWait > 0)
                %fprintf('Waiting %f seconds for resonant scanner to settle\n',timeToWait);
                pause(timeToWait);
            end
        end
        
        function timeToWait = getRemainingResSettlingTime(obj,settleTime)
            if nargin < 2 || isempty(settleTime)
                settleTime = max(0.5,obj.hScan.mdfData.resonantScannerSettleTime);
            end
            
            timeSinceLastAOUpdate = etime(clock,obj.resonantScannerLastUpdate);
            timeToWait = max(0, settleTime-timeSinceLastAOUpdate);
        end
        
        function parkGalvo(obj)
           assert(~obj.acquisitionActive,'Cannot park galvo while scanner is active');
           
           if ~isempty(obj.hScan.xGalvo)
               obj.hScan.xGalvo.hDevice.park();
           end
           obj.hScan.yGalvo.hDevice.park();
        end
        
        function centerGalvo(obj)
           assert(~obj.acquisitionActive,'Cannot center galvo while scanner is active');
           
           if ~isempty(obj.hScan.xGalvo)
               obj.hScan.xGalvo.hDevice.center();
           end
           obj.hScan.yGalvo.hDevice.center();
        end
            
        function pointResAmplitudeDeg(obj,angle)
            volts = obj.hScan.zzzResonantFov2Volts(angle/obj.hScan.mdfData.resonantAngularRange);
            obj.pointResAmplitudeVolts(volts);
        end
        
        function pointResAmplitudeVolts(obj,val)
            assert(~obj.acquisitionActive,'Cannot change resonant scanner amplitude while scan is active');
            obj.resonantScannerActivate(true,val);
        end
        
        function updateLiveValues(obj,regenAO)
            if nargin < 2
                regenAO = true;
            end
            
            if obj.acquisitionActive
                try
                    if regenAO
                        obj.hScan.hSI.hWaveformManager.updateWaveforms();
                    end
                    
                    obj.updateTaskCfg(true);
                catch ME
                    % ignore DAQmx Error 200015 since it is irrelevant here
                    % Error message: "While writing to the buffer during a
                    % regeneration the actual data generated might have
                    % alternated between old data and new data."
                    if isempty(strfind(ME.message, '200015'))
                        rethrow(ME)
                    end
                end
            else
                if obj.hScan.keepResonantScannerOn
                    obj.resonantScannerActivate();
                end
                
                % if the parking position for the Galvo was updated, apply
                % the new settings.
                obj.parkGalvo();
            end
        end
    end
    
    %% Private Methods
    methods (Hidden)
        function v = nextResonantVoltage(obj)
            v = obj.hScan.scannerset.resonantScanVoltage(obj.hScan.currentRoiGroup);
        end
        
        function v = nextResonantFov(obj)
            v = obj.hScan.scannerset.resonantScanFov(obj.hScan.currentRoiGroup);
        end
    end
    
    methods (Access = private)
        function resonantScannerUpdateOutputVolts(obj,val)
            if isempty(val)
                val = 0;
            end
            
            if abs(val - obj.resonantScannerLastWrittenValue) > 0.0001
                obj.resonantScannerLastUpdate = clock;
            end
            
            if ~obj.hScan.disableResonantZoomOutput
                if ~isempty(obj.hAOTaskResonantScannerZoom)
                    obj.hAOTaskResonantScannerZoom.setChannelOutputValues(val);
                end
                
                if ~isempty(obj.hDOTaskResonantScannerEnable)
                    obj.hDOTaskResonantScannerEnable.setChannelOutputValues(val > 0);
                end
            end
            
            if val
                if obj.hScan.scanModeIsResonant
                    obj.hScan.flagZoomChanged = true;
                    obj.hScan.linePhase = obj.hScan.zzzEstimateLinePhase(val);
                end
                
                if isfield(obj.hScan.mdfData, 'simulatedResonantMirrorPeriod')
                    obj.hAcqEngine.acqParamSimulatedResonantPeriod = obj.hScan.mdfData.simulatedResonantMirrorPeriod;
                end
            else
                obj.hAcqEngine.acqParamSimulatedResonantPeriod = 0;
            end
            
            obj.resonantScannerLastWrittenValue = val;
            notify(obj.hScan,'resonantScannerOutputVoltsUpdated');
        end
        
        function initializeTasks(obj) 
            try
                scannerName = obj.hScan.name;
                
                if obj.resonantMirrorExists
                    % create resonant mirror enable task
                    if ~isempty(obj.hScan.mdfData.resonantEnableTerminal)
                        ch = obj.hScan.mdfData.resonantEnableTerminal;
                        assert(ischar(ch),'Invalid channel ID for resonant scanner enable.');
                        
                        [~,~,~,~,results] = regexpi(ch,'D(.)\.(.)');
                        assert(numel(results) == 1,'Invalid channel ID for resonant scanner enable.');
                        assert(str2double(results{1}{1}) ~= 1, 'Invalid channel ID for resonant scanner enable.');
                        
                        obj.hDOTaskResonantScannerEnable = dabs.vidrio.ddi.DoTask(obj.hFpga, [scannerName '-GalvoCtrlResonantScannerEnable']);
                        obj.hDOTaskResonantScannerEnable.addChannel(ch);
                    end
                    
                    % set up AO task to control resonant amplitude
                    if ~isempty(obj.hScan.mdfData.resonantZoomAOChanID)
                        obj.hAOTaskResonantScannerZoom = dabs.vidrio.ddi.AoTask(obj.hFpga,[scannerName '-GalvoCtrlResonantScannerZoomVolts']);
                        obj.hAOTaskResonantScannerZoom.addChannel(obj.hScan.mdfData.resonantZoomAOChanID);
                        obj.hAOTaskResonantScannerZoom.channelRanges = [0 1.01*obj.hScan.mdfData.rScanVoltsPerOpticalDegree*obj.hScan.mdfData.resonantAngularRange];
                    end
                    
                    obj.resonantScannerActivate(false); % set output to zero
                end
                
                % set up AO ask to control the galvo positions
                obj.hAOTaskGalvo = dabs.vidrio.ddi.AoTask(obj.hFpga, [scannerName '-GalvoCtrlGalvoPosition']);
                if obj.xGalvoExists
                    obj.hAOTaskGalvo.addChannel(obj.hScan.mdfData.galvoAOChanIDX,'X Galvo Control');
                end
                obj.hAOTaskGalvo.addChannel(obj.hScan.mdfData.galvoAOChanIDY,'Y Galvo Control');
                obj.hAOTaskGalvo.sampleMode = 'finite';
                obj.hAOTaskGalvo.allowRetrigger = true;
                
                % set up AO task to control beams
                beamDaqId = obj.hScan.beamDaqID;
                obj.hAOTaskBeams = dabs.vidrio.ddi.AoTask(obj.hFpga, [scannerName '-BeamCtrl']);
                if ~isempty(beamDaqId)
                    hBms = obj.hScan.hSI.hBeams;
                    beamsMdf = hBms.mdfData;
                    daqDev = beamsMdf.beamDaqDevices{beamDaqId};
                    assert(strcmp(daqDev, obj.hScan.mdfData.acquisitionDeviceId), 'Beams must be controlled by aquisition device.');
                    
                    daqInfo = beamsMdf.beamDaqs(beamDaqId);
                    chInds = hBms.globalID2DaqID(obj.hScan.mdfData.beamIds);
                    for i = 1:numel(chInds)
                        chInd = chInds(i);
                        obj.hAOTaskBeams.addChannel(daqInfo.chanIDs(chInd), daqInfo.displayNames{chInd});
                        obj.hAOTaskBeams.channelRanges = arrayfun(@(v){[0 v]}, daqInfo.voltageRanges);
                    end
                    
                    obj.hAOTaskBeams.sampleMode = 'finite';
                    obj.hAOTaskBeams.allowRetrigger = true;
                end
                
                % set up AO task to control piezo
                obj.hAOTaskZ = dabs.vidrio.ddi.AoTask(obj.hFpga, [scannerName '-ZCtrl']);
                hFastZ = obj.hScan.hSI.hFastZ;
                [tf, idx] = ismember(scannerName,hFastZ.scannerMapKeys);
                if tf || ~isempty(hFastZ.defaultScannerId)
                    if tf
                        zScannerID = hFastZ.scannerMapIds(idx);
                    else
                        zScannerID = hFastZ.defaultScannerId;
                    end
                    
                    zScannerInfo = hFastZ.mdfData.actuators(zScannerID);
                    assert(strcmp(zScannerInfo.daqDeviceName, obj.hScan.mdfData.acquisitionDeviceId), 'FastZ must be controlled by aquisition device.');
                    obj.hAOTaskZ.addChannel(zScannerInfo.cmdOutputChanID);
                    
                    obj.hAOTaskZ.sampleMode = 'finite';
                    obj.hAOTaskZ.allowRetrigger = true;
                end
                
            catch ME
                delete(obj)
                rethrow(ME);
            end
            
            obj.resScanBoxCtrlInitialized = true;
        end
        
        function setupSampleClk(obj)
            if obj.useScannerSampleClk
                scannerAo = obj.hScan.hSI.hWaveformManager.scannerAO;
                
                if obj.hScan.scanModeIsLinear
                    obj.hAcqEngine.acqParamSampleClkPulsesPerPeriod = scannerAo.ao_samplesPerTrigger.G;
                    obj.hAcqEngine.acqParamLinearSampleClkPulseDuration = obj.hScan.sampleRateCtlDecim;
                else
                    obj.scannerSampsPerPeriod = floor(obj.hScan.sampleRateCtl/obj.hScan.scannerFrequency);
                    
                    obj.waveformLenthPeriods.G = round(obj.hScan.scannerFrequency * size(scannerAo.ao_volts.G,1) / obj.hScan.sampleRateCtl);
                    obj.waveformResampLength.G = obj.waveformLenthPeriods.G * obj.scannerSampsPerPeriod;
                    
                    if isfield(scannerAo.ao_volts, 'Z')
                        obj.waveformLenthPeriods.Z = round(obj.hScan.scannerFrequency * size(scannerAo.ao_volts.Z,1) / obj.hScan.sampleRateCtl);
                        obj.waveformResampLength.Z = obj.waveformLenthPeriods.Z * obj.scannerSampsPerPeriod;
                    end
                    
                    obj.hAcqEngine.acqParamSampleClkPulsesPerPeriod = obj.scannerSampsPerPeriod;
                end
            end
        end
             
        function updateTaskCfg(obj, isLive)            
            if nargin < 2 || isempty(isLive)
                isLive = false;
            end
            
            beamsActive = ~isempty(obj.hAOTaskBeams.channels);
            zActive = ~isempty(obj.hAOTaskZ.channels) && obj.hScan.hSI.hFastZ.outputActive;
            
            scannerAo = obj.hScan.hSI.hWaveformManager.scannerAO;
            ss = obj.hScan.scannerset;
            
            if obj.hScan.scanModeIsLinear
                v = 0;
            else
                v = max(scannerAo.ao_volts.R);
            end
            obj.resonantScannerUpdateOutputVolts(v);
            
            if obj.xGalvoExists
                galvoPoints = scannerAo.ao_volts.G;
            else
                galvoPoints = scannerAo.ao_volts.G(:,2);
            end
            galvoSamplesPerFrame = scannerAo.ao_samplesPerTrigger.G;
            galvoBufferLengthNew = size(galvoPoints,1);
            assert(galvoBufferLengthNew > 0, 'AO generation error. Galvo control waveform length is zero.');
            assert(~mod(galvoBufferLengthNew,galvoSamplesPerFrame),'Length of dataPoints has to be divisible by samplesPerFrame');
            
            if beamsActive
                hBeams = obj.hScan.hSI.hBeams;
                assert(~hBeams.enablePowerBox || ((hBeams.powerBoxStartFrame == 1) && isinf(hBeams.powerBoxEndFrame)),...
                    'Time varying power box is not supported.');
                if hBeams.hasPowerBoxes
                    beamPoints = scannerAo.ao_volts.Bpb;
                else
                    beamPoints = scannerAo.ao_volts.B;
                end
                beamBufferLengthNew = size(beamPoints,1);
            else
                beamBufferLengthNew = 0;
            end
            
            if zActive
                zPoints = scannerAo.ao_volts.Z;
                zBufferLengthNew = size(zPoints, 1);
                zSamplesPerTrigger = size(zPoints, 1);
            else
                zBufferLengthNew = 0;
            end
            
            if obj.useScannerSampleClk && ~obj.hScan.scanModeIsLinear
                % waveforms need to be resampled to have round number of
                % samples per resonant period
                N = galvoBufferLengthNew-1;
                galvoPoints = interp1(0:N,galvoPoints,linspace(0,N,obj.waveformResampLength.G)');
                if zActive
                    N = zBufferLengthNew-1;
                    zPoints = interp1(0:N,zPoints,linspace(0,N,obj.waveformResampLength.Z)');
                end
            end
            
            if isLive
                assert(obj.galvoBufferLength == galvoBufferLengthNew, 'Buffer length can''t change.');
                assert(obj.beamBufferLength == beamBufferLengthNew, 'Buffer length can''t change.');
                assert(obj.zBufferLength == zBufferLengthNew, 'Buffer length can''t change.');
            else
                obj.hAOTaskGalvo.abort();
                obj.hAOTaskBeams.abort();
                obj.hAOTaskZ.abort();
                
                obj.galvoBufferLength = galvoBufferLengthNew;
                obj.beamBufferLength = beamBufferLengthNew;
                obj.zBufferLength = zBufferLengthNew;
                
                obj.hScan.hSI.hBeams.streamingBuffer = false;
                
                if obj.useScannerSampleClk
                    obj.hAOTaskGalvo.sampleRate = 2e6; % dummy; wont be actual rate
                    obj.hAOTaskGalvo.startTrigger = obj.hScan.hTrig.sampleClkTermInt;
                    obj.hAOTaskGalvo.samplesPerTrigger = 1;
                    obj.hAOTaskGalvo.allowEarlyTrigger = false;
                else
                    obj.hAOTaskGalvo.sampleRate = obj.hScan.sampleRateCtl;
                    obj.hAOTaskGalvo.startTrigger = obj.hScan.hTrig.sliceClkTermInt;
                    obj.hAOTaskGalvo.samplesPerTrigger = galvoSamplesPerFrame;
                    obj.hAOTaskGalvo.allowEarlyTrigger = true;
                end
                
                if beamsActive
                    obj.hAOTaskBeams.sampleMode = 'finite';
                    if obj.hScan.scanModeIsLinear
                        if obj.useScannerSampleClk
                            obj.hAOTaskBeams.sampleRate = 2e6; % dummy; wont be actual rate
                            obj.hAOTaskBeams.startTrigger = obj.hScan.hTrig.sampleClkTermInt;
                            obj.hAOTaskBeams.samplesPerTrigger = 1;
                            obj.hAOTaskBeams.allowEarlyTrigger = false;
                        else
                            obj.hAOTaskBeams.sampleRate = ss.beams.sampleRateHz;
                            obj.hAOTaskBeams.startTrigger = obj.hScan.hTrig.sliceClkTermInt;
                            obj.hAOTaskBeams.samplesPerTrigger = scannerAo.ao_samplesPerTrigger.B;
                            obj.hAOTaskBeams.allowEarlyTrigger = true;
                        end
                    else
                        obj.hAOTaskBeams.sampleRate = ss.beams.sampleRateHz;
                        obj.hAOTaskBeams.samplesPerTrigger = scannerAo.ao_samplesPerTrigger.B;
                        obj.hAOTaskBeams.startTrigger = obj.hScan.hTrig.beamClkTermInt;
                        obj.hAOTaskBeams.allowEarlyTrigger = false;
                    end
                end
                
                if zActive
                    if obj.useScannerSampleClk
                        obj.hAOTaskZ.sampleRate = 2e6; % dummy; wont be actual rate
                        obj.hAOTaskZ.startTrigger = obj.hScan.hTrig.sampleClkTermInt;
                        obj.hAOTaskZ.samplesPerTrigger = 1;
                        obj.hAOTaskZ.allowEarlyTrigger = false;
                    else
                        obj.hAOTaskZ.sampleRate = ss.fastz.sampleRateHz;
                        obj.hAOTaskZ.startTrigger = obj.hScan.hTrig.volumeClkTermInt;
                        obj.hAOTaskZ.samplesPerTrigger = zSamplesPerTrigger;
                        obj.hAOTaskZ.allowEarlyTrigger = true;
                    end
                end
            end
            
            if ~obj.simulated
                obj.hAOTaskGalvo.writeOutputBuffer(galvoPoints);
                if beamsActive
                    obj.hAOTaskBeams.writeOutputBuffer(beamPoints);
                end
                if zActive
                    obj.hAOTaskZ.writeOutputBuffer(zPoints);
                end
            end
        end
    end
    
    %% Property Set Methods
    methods        
        function value = get.galvoParkVoltsX(obj)
            value = obj.hScan.mdfData.galvoParkDegreesX * obj.hScan.mdfData.galvoVoltsPerOpticalDegreeX;
        end
        
        function value = get.galvoParkVoltsY(obj)
            value = obj.hScan.mdfData.galvoParkDegreesY * obj.hScan.mdfData.galvoVoltsPerOpticalDegreeY;
        end
    end
end


%--------------------------------------------------------------------------%
% Control.m                                                                %
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
