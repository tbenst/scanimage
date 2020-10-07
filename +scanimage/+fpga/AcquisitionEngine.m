classdef AcquisitionEngine < dabs.vidrio.rdi.Device
    
    properties
        acqParamChannelOffsets;
        acqParamChannelsInvert;
        
        acqStatusStateMachineState;
        acqStatusRawChannelData;
        acqStatusPeriodTriggerSettled;
        acqStatusPeriodTriggerPeriod;
    end
    
    properties (Hidden)
        registerMap = initRegs();
        
        LOGICAL_CHANNEL_SOURCES = {'AI0' 'AI1' 'AI2' 'AI3' 'PH0' 'PH1' 'PH2' 'PH3'};
    end
    
    %% Lifecycle
    methods
        function obj = AcquisitionEngine(varargin)
            obj = obj@dabs.vidrio.rdi.Device(varargin{:});
        end
    end
    
    %% User methods
    methods
        function smReset(obj)
            obj.smCmd = 38;
        end
        
        function smEnable(obj)
            obj.smCmd = 37;
        end
        
        function softStartTrig(obj)
            obj.smCmd = 39;
        end
        
        function softNextTrig(obj)
            obj.smCmd = 40;
        end
        
        function softStopTrig(obj)
            obj.smCmd = 41;
        end
        
        function resetDataScope(obj)
            obj.smCmd = 51;
        end
        
        function startDataScope(obj)
            obj.smCmd = 52;
        end
        
        function writeAcqPlan(obj,addr,newEntry,frameClockState,numPeriods)
            if newEntry
                v = uint32(2^8) + uint32(frameClockState*2^7) + uint32(bitand(numPeriods,2^7-1));
            else
                v = uint32(bitand(numPeriods,2^8-1));
            end
            
            v = v + uint32(addr * 2^9);
            
            obj.acqPlanWriteReg = v;
        end
        
        function writeMaskTable(obj,addr,val)
            accumBits = 12;
            v = uint32(addr*2^accumBits) + uint32(bitand(val,2^accumBits-1));
            obj.maskTableWriteReg = v;
        end
        
    end
    
    %% Prop Access
    methods
        function v = get.acqParamChannelOffsets(obj)
            r1 = obj.acqParamChannelOffsetsReg1;
            r2 = obj.acqParamChannelOffsetsReg2;
            
            v = [typecast(r1,'int16') typecast(r2,'int16')];
        end
        
        function set.acqParamChannelOffsets(obj,v)
            obj.acqParamChannelOffsetsReg1 = typecast(int16(v(1:2)),'uint32');
            obj.acqParamChannelOffsetsReg2 = typecast(int16(v(3:4)),'uint32');
        end
        
        function v = get.acqParamChannelsInvert(obj)
            v = double(obj.acqParamChannelsInvertReg);
            v = logical(bitand(v,2.^(0:3)));
        end
        
        function set.acqParamChannelsInvert(obj,val)
            v = uint32(val(1));
            for c = 2:numel(val)
                v = bitor(v,(2^(c-1))*val(c));
            end
            obj.acqParamChannelsInvertReg = v;
        end
        
        function v = get.acqStatusRawChannelData(obj)
            r1 = obj.acqStatusRawChannelDataReg1;
            r2 = obj.acqStatusRawChannelDataReg2;
            
            v = [typecast(r1,'int16') typecast(r2,'int16')];
        end
        
        function v = get.acqStatusStateMachineState(obj)
            v = obj.acqStatusStateMachineStateReg;
            
            states = {'idle' 'wait for trigger' 'acquire' 'linear aquire'};
            v = states{v+1};
        end
        
        function v = get.acqStatusPeriodTriggerSettled(obj)
            v = logical(bitand(obj.acqStatusPeriodTriggerInfo, 2^31));
        end
        
        function v = get.acqStatusPeriodTriggerPeriod(obj)
            v = double(bitand(obj.acqStatusPeriodTriggerInfo, 2^16-1));
        end
    end
end

function s = initRegs()
    s.cmdRegs.smCmd = struct('address',100,'hide',true);
    
    s.dataRegs.acqPlanWriteReg = struct('address',104,'hide',true);
    s.dataRegs.acqPlanNumSteps = struct('address',108);
    
    s.dataRegs.maskTableWriteReg = struct('address',112,'hide',true);
    s.dataRegs.maskTableSize = struct('address',116);
    
    s.dataRegs.acqParamPeriodTriggerChIdx = struct('address',120);
    s.dataRegs.acqParamStartTriggerChIdx = struct('address',124);
    s.dataRegs.acqParamNextTriggerChIdx = struct('address',128);
    s.dataRegs.acqParamStopTriggerChIdx = struct('address',132);
    s.dataRegs.acqParamStartTriggerInvert = struct('address',292);
    s.dataRegs.acqParamNextTriggerInvert = struct('address',296);
    s.dataRegs.acqParamStopTriggerInvert = struct('address',300);
    s.dataRegs.acqParamPhotonChIdx = struct('address',136);
    s.dataRegs.acqParamPeriodTriggerDebounce = struct('address',140);
    s.dataRegs.acqParamTriggerDebounce = struct('address',144);
    s.dataRegs.acqParamLiveHoldoffAdjustEnable = struct('address',148);
    s.dataRegs.acqParamLiveHoldoffAdjustPeriod = struct('address',152);
    s.dataRegs.acqParamTriggerHoldoff = struct('address',156);
    s.dataRegs.acqParamChannelsInvertReg = struct('address',160,'hide',true);
    s.dataRegs.acqParamSamplesPerLine = struct('address',168);
    s.dataRegs.acqParamVolumesPerAcq = struct('address',172);
    s.dataRegs.acqParamTotalAcqs = struct('address',176);
    s.dataRegs.acqParamBeamClockAdvance = struct('address',180);
    s.dataRegs.acqParamBeamClockDuration = struct('address',184);
    s.dataRegs.acqParamDummyVal = struct('address',188);
    s.dataRegs.acqParamDisableDivide = struct('address',192);
    s.dataRegs.acqParamScalePower = struct('address',196);
    s.dataRegs.acqParamEnableBidi = struct('address',200);
    s.dataRegs.acqParamPhotonPulseDebounce = struct('address',204);
    s.dataRegs.acqParamMaskLSBs = struct('address',208);
    s.dataRegs.acqParamEnableLineTag = struct('address',164);
    
    s.dataRegs.acqParamAuxTriggerEnable = struct('address',232);
    s.dataRegs.acqParamAuxTrig1TriggerChIdx = struct('address',212);
    s.dataRegs.acqParamAuxTrig2TriggerChIdx = struct('address',216);
    s.dataRegs.acqParamAuxTrig3TriggerChIdx = struct('address',220);
    s.dataRegs.acqParamAuxTrig4TriggerChIdx = struct('address',224);
    s.dataRegs.acqParamAuxTriggerDebounce = struct('address',228);
    s.dataRegs.acqParamAuxTriggerInvert = struct('address',288);
    s.dataRegs.acqParamPeriodTriggerMaxPeriod = struct('address',236);
    s.dataRegs.acqParamPeriodTriggerSettledThresh = struct('address',240);
    s.dataRegs.acqParamSimulatedResonantPeriod = struct('address',284);
    
    s.dataRegs.acqParamSampleClkPulsesPerPeriod = struct('address',324);
    s.dataRegs.acqParamLinearSampleClkPulseDuration = struct('address',328);
    
    s.dataRegs.acqParamLinearMode = struct('address',260);
    s.dataRegs.acqParamLinearFramesPerVolume = struct('address',264);
    s.dataRegs.acqParamLinearFrameClkHighTime = struct('address',268);
    s.dataRegs.acqParamLinearFrameClkLowTime = struct('address',272);
    s.dataRegs.acqParamUniformSampling = struct('address',276);
    s.dataRegs.acqParamUniformBinSize = struct('address',280);
    
    s.dataRegs.acqParamChannelOffsetsReg1 = struct('address',340,'hide',true);
    s.dataRegs.acqParamChannelOffsetsReg2 = struct('address',344,'hide',true);
    
    s.dataRegs.i2cEnable = struct('address',348,'hide',true);
    s.dataRegs.i2cDebounce = struct('address',352,'hide',true);
    s.dataRegs.i2cAddress = struct('address',356,'hide',true);
    s.dataRegs.i2cSdaPort = struct('address',360,'hide',true);
    s.dataRegs.i2cSclPort = struct('address',364,'hide',true);
    
    s.dataRegs.scopeParamNumberOfSamples = struct('address',244);
	s.dataRegs.scopeParamDecimationLB2 = struct('address',248);
	s.dataRegs.scopeParamTriggerId = struct('address',252);
	s.dataRegs.scopeParamTriggerHoldoff = struct('address',256);
    
    s.dataRegs.acqStatusPeriodTriggerInfo = struct('address',400,'hide',true);
    s.dataRegs.acqStatusDataFifoOverflowCount = struct('address',404);
    s.dataRegs.acqStatusAuxFifoOverflowCount = struct('address',408);
    s.dataRegs.acqStatusStateMachineStateReg = struct('address',412,'hide',true);
    s.dataRegs.acqStatusVolumesDone = struct('address',416);
    s.dataRegs.scopeStatusFifoOverflowCount = struct('address',420);
    s.dataRegs.scopeStatusWrites = struct('address',424);
    
    s.dataRegs.acqStatusRawChannelDataReg1 = struct('address',500,'hide',true);
    s.dataRegs.acqStatusRawChannelDataReg2 = struct('address',504,'hide',true);
end


%--------------------------------------------------------------------------%
% AcquisitionEngine.m                                                      %
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
