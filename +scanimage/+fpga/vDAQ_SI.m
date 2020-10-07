classdef vDAQ_SI < dabs.vidrio.rdi.Device
    
    properties
        hClockCfg;
        
        hAfe;
        hMsadc;
        
        hAcqEngine;
        
        fifo_MultiChannelToHostU64;
        fifo_AuxDataToHostU64;
        fifo_DataScopeTargetToHost;
        
        hWaveGen;
        hWaveAcq;
        hDigitalWaveGen;
    end
    
    properties
        sampleClkRate;
        systemClock;
        
        pwmMeasChan;
        pwmPeriod;
        pwmPulseWidth;
    end
    
    properties (Hidden)
        bitfilePath;
        isR1 = false;
        
        nominalAcqSampleRate;
        nominalAcqLoopRate;
        
        scannerLastVal = 0;
        scannerLastUpdate= tic;
        lastFreq;
        
        % dummy props
        NominalResonantPeriodTicks;
        AutoAdjustTriggerHoldOff;
        MaxResonantPeriodTicks;
        MinResonantPeriodTicks;
        SettlingPeriods;
        
        ResScanFilterSamples;
        LaserTriggerFilterTicks;
        LaserTriggerDelay;
        LaserSampleWindowSize;
        
        DataScopeDoReset;
        
        oldInputRs;
        afe;
        
        spclOutputSignals = {};
        spclTriggerSignals = {};
        dioInputOptions = {};
        dioOutputOptions = {};
        
        defaultInternalSampleRate;
    end
    
    properties (Constant, Hidden)
        waveformTimebaseRate = 200e6;
        DIO_SPCL_OUTPUTS = {'si%d_pixelClk' 'si%d_acqClk' 'si%d_lineClk' 'si%d_beamClk' 'si%d_roiClk' 'si%d_sliceClk' 'si%d_volumeClk' 'si%d_ctlSampleClk' 'si%d_i2cAck'};
        WFM_SPCL_TRIGGERS = {'si%d_beamClk' 'si%d_roiClk' 'si%d_sliceClk' 'si%d_volumeClk' 'si%d_ctlSampleClk'};
    end
    
    %% Lifecycle
    methods
        function obj = vDAQ_SI(dev,simulate)
            if nargin < 2
                simulate = false;
            end
            
            obj = obj@dabs.vidrio.rdi.Device(dev,0,simulate);
            
            scanimage.fpga.vDAQ_SI.checkHardwareSupport();
            
            obj.hClockCfg = dabs.vidrio.vDAQ.ClkCfg(obj,'440000');
            obj.hMsadc = dabs.vidrio.vDAQ.Msadc(obj,'460000');
            obj.hAfe = obj.hMsadc;
            
            obj.fifo_MultiChannelToHostU64 = dabs.vidrio.rdi.Fifo(obj,'480000');
            obj.fifo_AuxDataToHostU64 = dabs.vidrio.rdi.Fifo(obj,'481000');
            obj.fifo_DataScopeTargetToHost = dabs.vidrio.rdi.Fifo(obj,'482000');
            
            obj.hAcqEngine = scanimage.fpga.AcquisitionEngine(obj,4194304+1024);
            obj.spclOutputSignals = cellfun(@(s){sprintf(s,0)},obj.DIO_SPCL_OUTPUTS);
            obj.spclTriggerSignals = cellfun(@(s){sprintf(s,0)},obj.WFM_SPCL_TRIGGERS);
            
            if obj.isR1
                obj.spclOutputSignals = [obj.spclOutputSignals cellfun(@(s){sprintf(s,1)},obj.DIO_SPCL_OUTPUTS)];
                obj.spclTriggerSignals = [obj.spclTriggerSignals cellfun(@(s){sprintf(s,1)},obj.WFM_SPCL_TRIGGERS)];
                
                obj.addprop('hLsadc');
                obj.hLsadc = dabs.vidrio.vDAQ.Lsadc(obj,'410000');
                
                nadc = 12;
                ndac = 12;
                
                inPorts = [0 1 2];
                outPorts = [0 1 3];
            else
                nadc = 4;
                ndac = 5;
                
                inPorts = [0 1];
                outPorts = [0 2];
            end
            
            p = arrayfun(@(p){arrayfun(@(i){sprintf('D%d.%d',p,i)},0:7)},inPorts);
            obj.dioInputOptions = [p{:}];
            p = arrayfun(@(p){arrayfun(@(i){sprintf('D%d.%d',p,i)},0:7)},outPorts);
            obj.dioOutputOptions = [p{:}];
            
            a = arrayfun(@(a){dabs.vidrio.ddi.rdi.ip.SlowWaveformAcq(obj,a)}, 5242880:65536:(5242880 + (nadc-1)*65536));
            obj.hWaveAcq = [a{:}];
            
            a = arrayfun(@(a){dabs.vidrio.ddi.rdi.ip.SlowWaveformGen(obj,a)}, 6291456:65536:(6291456 + (ndac-1)*65536));
            obj.hWaveGen = [a{:}];
            
            a = arrayfun(@(a){dabs.vidrio.ddi.rdi.ip.DigitalWaveformGen(obj,a)}, 3145728:65536:(3145728 + 3*65536));
            obj.hDigitalWaveGen = [a{:}];
        end
        
        function s = getRegMap(obj)
            obj.isR1 = obj.isR1 || (obj.deviceInfo.hardwareRevision > 0) || obj.simulate;
            
            s.dataRegs.T = struct('address',4194304+0);
            s.dataRegs.ledReg = struct('address',4194304+20,'hide',true);
            s.dataRegs.sampleClkCount = struct('address',4194304+4,'hide',true);
            
            s.dataRegs.systemClockL = struct('address',4194304+8,'hide',true);
            s.dataRegs.systemClockH = struct('address',4194304+12,'hide',true);
            
            s.dataRegs.dio_i = struct('address',4194304+24);
            s.dataRegs.rtsi_i = struct('address',4194304+28);
            
            s.dataRegs.pwmMeasChanReg = struct('address',4194304+92,'hide',true);
            s.dataRegs.pwmMeasDebounce = struct('address',4194304+96);
            s.dataRegs.pwmMeasPeriodMax = struct('address',4194304+100);
            s.dataRegs.pwmMeasPeriodReg = struct('address',4194304+104,'hide',true);
            s.dataRegs.pwmMeasHighTimeReg = struct('address',4194304+108,'hide',true);
            
            s.dataRegs.sysClk200_en = struct('address',4194304+36,'hide',true);
            s.dataRegs.sysClk100_en = struct('address',4194304+40,'hide',true);
            s.dataRegs.ioClk_en = struct('address',4194304+48,'hide',true);
            s.dataRegs.ioClk40_en = struct('address',4194304+52,'hide',true);
            s.dataRegs.adcSpiClkOut_en = struct('address',4194304+56,'hide',true);
            s.dataRegs.dacSpiClkOut_en = struct('address',4194304+60,'hide',true);
            s.dataRegs.afeSelect = struct('address',4194304+64,'hide',true);
            
            if obj.isR1
                s.dataRegs.ioClk_oxen = struct('address',4194304+44,'hide',true);
                s.dataRegs.ver = struct('address',4194304+200,'hide',true);
                s.dataRegs.syncTriggerReset = struct('address',4194304+68,'hide',true);
            else
                s.dataRegs.moduleId = struct('address',4194304+68,'hide',true);
            end
            
            ndio = 39 + 8*obj.isR1;
            for i = 0:ndio
                s.dataRegs.(['digital_o_' num2str(i)]) = struct('address',4194304+200+i*4,'hide',true);
            end
        end
        
        function delete(obj)
            delete(obj.hWaveGen);
            delete(obj.hWaveAcq);
            delete(obj.hDigitalWaveGen);
            
            delete(obj.fifo_MultiChannelToHostU64);
            delete(obj.fifo_AuxDataToHostU64);
            delete(obj.fifo_DataScopeTargetToHost);
            
            delete(obj.hAcqEngine);
            obj.delete@dabs.vidrio.rdi.Device;
        end
    end
    
    %% User methods
    methods
        function loadDesign(obj,varargin)
            if nargin > 1
                obj.loadDesign@dabs.vidrio.rdi.Device(varargin{:});
            else
                bfPath = fullfile(fileparts(which(mfilename('fullpath'))),'bitfiles');
                hwName = sprintf('vDAQR%d_', obj.deviceInfo.hardwareRevision);
                
                if ~obj.deviceInfo.designLoaded
                    obj.loadDesign@dabs.vidrio.rdi.Device(fullfile(bfPath, [hwName 'Firmware.dbs']));
                end
                
                obj.bitfilePath = fullfile(bfPath, [hwName 'SI.dbs']);
                obj.loadDesign@dabs.vidrio.rdi.Device(obj.bitfilePath);
            end
        end
        
        function run(obj)
            if ~obj.simulate
                obj.loadDesign();
            end
        end
        
        function configureInternalSampleClock(obj)
            % configure clock chip for internal clock
            obj.nominalAcqSampleRate = obj.defaultInternalSampleRate;
            obj.nominalAcqLoopRate = obj.nominalAcqSampleRate;
            
            if ~obj.simulate
                obj.hClockCfg.setupClk('internal', obj.defaultInternalSampleRate, obj.defaultInternalSampleRate, 1, 1, nan, nan, obj.isR1);
                assert(obj.moduleId || ~obj.isR1, 'High speed analog module not detected.');
                obj.afe = obj.moduleId;
            end
        end
        
        function configureExternalSampleClock(obj,rate,multiplier)
            % configure clock chip for external clock
            sRate = rate*multiplier;
            assert(sRate >= 62.5e6, 'Minimum sample rate is 62.5 MHz. Adjust external clock frquency and/or multiplier.');
            assert(sRate <= 125e6, 'Maximum sample rate is 125 MHz. Adjust external clock frquency and/or multiplier.');
            
            obj.nominalAcqSampleRate = sRate;
            obj.nominalAcqLoopRate = obj.nominalAcqSampleRate;
            
            if ~obj.simulate
                obj.hClockCfg.setupClk('external', rate, sRate, 1, 1, nan, nan, obj.isR1);
                assert(obj.moduleId || ~obj.isR1, 'High speed analog module not detected.');
                obj.afe = obj.moduleId;
            end
        end
        
        function l = checkPll(obj)
            l = obj.hClockCfg.checkPll();
            
            if ~nargout
                if ~l
                    app = 'n''t';
                else
                    app = '';
                end
                disp(['Was' app ' locked..']);
            end
        end
        
        function lockPll(obj)
            l = obj.hClockCfg.lockPll();
            assert(l, 'FPGA clocking error');
        end
        
        function startMsadc(obj)
            if obj.isR1
                obj.hClockCfg.ch1Mute = 0;
            else
                obj.hClockCfg.ch0Mute = 0;
            end
            obj.hClockCfg.writeSettingsToDevice();
            pause(0.1);
            
            obj.hMsadc.configurePllForClkRate(obj.nominalAcqSampleRate);
            obj.hMsadc.resetAcqEngine();
            if obj.isR1
                obj.syncTriggerReset = 1;
                obj.syncTriggerReset = 0;
            end
            pause(0.01);
            obj.verifyMsadcData();
        end
        
        function verifyMsadcData(obj)
            assert(~isinf(obj.sampleClkRate) && ~isnan(obj.sampleClkRate),'Analog front end sample clock not running')
            
            obj.hMsadc.usrReqTestPattern = 1;
            inv = obj.hAcqEngine(1).acqParamChannelsInvertReg;
            obj.hAcqEngine(1).acqParamChannelsInvertReg = 0;
            
            try
                for i=1:100
                    assert(all(obj.hAcqEngine(1).acqStatusRawChannelData(:) == 24160),'Analog front end data error.');
                end
            catch ME
                obj.hAcqEngine(1).acqParamChannelsInvertReg = inv;
                obj.hMsadc.usrReqTestPattern = 0;
                ME.rethrow();
            end
            
            obj.hAcqEngine(1).acqParamChannelsInvertReg = inv;
            obj.hMsadc.usrReqTestPattern = 0;
        end
        
        function val = setChannelsInputRanges(obj,val)
            v = cellfun(@(f)f(2)*2,val);
            
            % channels 1/2 and channels 3/4 must have same setting
            
            if isempty(obj.oldInputRs)
                obj.oldInputRs = v;
            else
                chg = obj.oldInputRs ~= v;
                
                if sum(chg) == 1
                    ch = find(chg);
                    buddy = floor((ch-1)/2)*2 + 1 + mod(ch,2);
                    v(buddy) = v(chg);
                end
            end
            
            v = obj.hAfe.setInputRanges(v);
            obj.oldInputRs = v;
            val = arrayfun(@(f){[-f/2 f/2]}, v);
        end
        
        function val = setChannelsFilter(obj,val)
            if isnan(val) || (val > 31)
                powerMode = 'high';
            else
                powerMode = 'low';
            end
            
            v = val;
            v(isnan(val)) = 0;
            
            obj.hAfe.setVgaSettings('dcOffsetEnable',0,'filterFreq',v,'powerMode',powerMode);
        end
        
        function [id, port, line] = dioNameToId(obj,ch)
            if strncmpi(ch,'rtsi',4)
                line = str2double(ch(5:end));
                id = 24 + 8*obj.isR1 + line;
                assert(id < (40 + 8*obj.isR1), 'Invalid RTSI channel ID.');
                port = 'r';
            else
                [~,~,~,~,results] = regexpi(ch,'^D(.)\.(.)');
                assert(numel(results) == 1,'Invalid channel ID.');
                
                port = str2double(results{1}{1});
                line = str2double(results{1}{2});
                
                assert((port >= 0) && (port <= (2 + obj.isR1)),'Invalid channel ID.');
                assert((line >= 0) && (line <= 7),'Invalid channel ID.');
                
                id = port * 8 + line;
            end
        end
        
        function chId = digitalNameToOutputId(obj,ch,suppressOutputPortError)
            chId = obj.dioNameToId(ch);
            assert((chId < 8*(1+obj.isR1)) || (chId >= 8*(2+obj.isR1)) || suppressOutputPortError,...
                'Cannot use digital port %d for outputs.', 1+obj.isR1);
        end
        
        function chId = setDioOutput(obj,chId,outputValue)
            outputHighZ = isempty(outputValue) || all(isnan(outputValue)) || (ischar(outputValue) && strcmpi(outputValue,'Z'));
            
            if ischar(chId)
                chId = obj.digitalNameToOutputId(chId,outputHighZ);
            end
            
            if outputHighZ
                v = 0;
            elseif ischar(outputValue)
                [tf,srcId] = ismember(outputValue,obj.spclOutputSignals);
                if tf
                    v = srcId+2;
                else
                    [~,~,~,~,results] = regexpi(outputValue,'^task(.)\.(.)');
                    if numel(results) == 1
                        task = str2double(results{1}{1});
                        line = str2double(results{1}{2});

                        assert((task >= 1) && (task <= numel(obj.hDigitalWaveGen)),'Invalid task selection');
                        assert((line >= 0) && (line <= 7),'Invalid task line selection');

                        v = numel(obj.spclOutputSignals) - 5 + task*8 + line;
                    else
                        error('Invalid signal selection.');
                    end
                end
            else
                v = logical(outputValue)+1;
            end
            
            obj.(['digital_o_' num2str(chId)]) = v;
        end
        
        function v = getDioOutput(obj,channel)
            if ischar(channel)
                channel = obj.digitalNameToOutputId(channel);
            end
            v = obj.(['digital_o_' num2str(channel)]);
            
            tskStrtInd = numel(obj.spclOutputSignals) + 3;
            
            if ~v
                v = nan;
            elseif v < 3
                v = logical(v-1);
            elseif v < tskStrtInd
                v = obj.spclOutputSignals{v-2};
            else
                c = v-tskStrtInd;
                tsk = floor(c/8) + 1;
                line = mod(c,8);
                v = sprintf('Task%d.%d',tsk,line);
            end
        end
        
        function v = getDioInputVal(obj,channel)
            if ischar(channel)
                channel = obj.dioNameToId(channel);
            end
            
            ndio = 8*(3+obj.isR1);
            if channel < ndio
                v = logical(bitand(obj.dio_i,2^channel));
            else
                v = logical(bitand(obj.rtsi_i,2^(channel-ndio)));
            end
        end

        function id = signalNameToTriggerId(obj, signal)
            [tf, n] = ismember(signal,obj.spclTriggerSignals);
            if tf
                id = n + 39 + 8*obj.isR1;
            else
                try
                    id = obj.dioNameToId(signal);
                catch
                    error('Invalid trigger terminal.');
                end
            end
        end
    end
    
    %% Prop Access
    methods
        function v = get.sampleClkRate(obj)
            r = obj.sampleClkCount;
            if r == 8388607
                v = nan;
            else
                v = calcClkRate(r,200e6);
            end
        end
        
        function v = get.systemClock(obj)
            obj.systemClockL = 0;
            v = uint64(obj.systemClockL) + uint64(obj.systemClockH) * 2^32;
        end
        
        function set.afe(obj,v)
            obj.hClockCfg.ch0Mute = 1;
            obj.hClockCfg.ch1Mute = 1;
            
            switch v
                case 1
                    assert(obj.moduleId == 1, 'Module not present.');
                    obj.afeSelect = 1;
                    obj.hAfe = obj.hMsadc;
                    obj.startMsadc();
                    
                otherwise
                    error('Invalid afe selection.');
            end
            
            obj.afe = v;
        end
        
        function v = get.pwmMeasChan(obj)
            r = obj.pwmMeasChanReg;
            if r > 39
                v = [];
            elseif r > 23
                v = sprintf('RTSI%d',r-24);
            else
                prt = floor(r/8);
                lin = mod(r,8);
                v = sprintf('D%d.%d',prt,lin);
            end
        end
        
        function set.pwmMeasChan(obj,v)
            obj.pwmMeasChanReg = obj.dioNameToId(v);
        end
        
        function v = get.pwmPeriod(obj)
            r = obj.pwmMeasPeriodReg;
            
            if r < 2 || r >= obj.pwmMeasPeriodMax
                v = [];
            else
                v = double(obj.pwmMeasPeriodReg) / 200e6;
            end
        end
        
        function v = get.pwmPulseWidth(obj)
            r = obj.pwmMeasHighTimeReg;
            
            if r >= obj.pwmMeasPeriodMax
                v = [];
            else
                v = double(obj.pwmMeasHighTimeReg) / 200e6;
            end
        end
        
        function v = get.defaultInternalSampleRate(obj)
            v = (120+5*obj.isR1) * 1e6;
        end
    end
    
    %% Static
    methods (Static)
        function checkHardwareSupport(devs)
            if ~nargin
                devs = (1:dabs.vidrio.rdi.Device.getDriverInfo.numDevices) - 1;
            end
            
            if strcmp(scanimage.SI.VERSION_MINOR, '2019b') && ~strcmp(scanimage.SI.VERSION_MINOR, '1')
                error('A new bugfix release of ScanImage 2019b is available that fixes important issues. Please contact support@vidriotech.com for details. SI will now exit.');
            end
            
            for i = devs
                s = dabs.vidrio.rdi.Device.getDeviceInfo(i-1);
                if s.hardwareRevision
                    if strcmp(s.firmwareVersion, 'A0')
                        error('A firmware update is required for your vDAQ in order to run this version of ScanImage. Please contact support@vidriotech.com for details.');
                    elseif ~strcmp(s.firmwareVersion, 'A1')
                        error('The firmware version of your vDAQ device is not compatible with this version of ScanImage. Please contact support@vidriotech.com for details.');
                    end
                elseif ~strcmp(s.firmwareVersion, 'A0')
                    error('The firmware version of your vDAQ device is not compatible with this version of ScanImage. Please contact support@vidriotech.com for details.');
                end
            end
        end
    end
end

function r = calcClkRate(v,measClkRate)
    if v == 2^32-1
        r = nan;
    else
        measClkPeriod = 1/measClkRate;
        TperNticks = double(v)*measClkPeriod;
        targetClkPeriod = TperNticks / 2^19;
        r = (1/targetClkPeriod) / 1e6;
    end
end


%--------------------------------------------------------------------------%
% vDAQ_SI.m                                                                %
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
