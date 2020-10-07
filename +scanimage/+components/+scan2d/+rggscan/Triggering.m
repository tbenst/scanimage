classdef Triggering < scanimage.interfaces.Class
    %% FRIEND PROPS
    
    %%% The ScanImage timing signals
    properties
        periodClockIn = 'D1.0';
        acqTriggerIn = '';
        nextFileMarkerIn = '';
        acqStopTriggerIn = '';
        laserTriggerIn = '';
        auxTrigger1In = '';
        auxTrigger2In = '';
        auxTrigger3In = '';
        auxTrigger4In = '';
        
        frameClockOut = '';
        beamModifiedLineClockOut = '';
        volumeTriggerOut = '';
        
        sampleClkTermInt = '';
        beamClkTermInt = '';
        sliceClkTermInt = '';
        volumeClkTermInt = '';
    end
    
    %%% Acq flow trigger input polarity 
    properties (Hidden)
        acqTriggerOnFallingEdge = false;
        nextFileMarkerOnFallingEdge = false;
        acqStopTriggerOnFallingEdge = false;
        
        enabled = true; % querried in si controller
        routes = {};
        routesEnabled = true;
    end

    %% INTERNAL PROPERTIES
    properties (Hidden, SetAccess=immutable)
        hScan;
        hAcq;
        hCtl;
        hFpga;
        hFpgaAE;
        
        hFpgaRouteRegistry;
        simulated = false;
        
        externalTrigTerminalOptions;
    end
    
    
    %% Lifecycle
    methods
        function obj = Triggering(hScan,simulated)
            % Validate input arguments
            obj.hScan = hScan;
            obj.hAcq = obj.hScan.hAcq;
            obj.hFpga = obj.hAcq.hFpga;
            obj.hFpgaAE = obj.hAcq.hAcqEngine;
            obj.hCtl = obj.hScan.hCtl;
            
            aeId = obj.hScan.mdfData.acquisitionEngineIdx-1;
            obj.sampleClkTermInt = sprintf('si%d_ctlSampleClk',aeId);
            obj.beamClkTermInt = sprintf('si%d_beamClk',aeId);
            obj.sliceClkTermInt = sprintf('si%d_sliceClk',aeId);
            obj.volumeClkTermInt = sprintf('si%d_volumeClk',aeId);

            obj.simulated = simulated;
            obj.externalTrigTerminalOptions = [{''} obj.hFpga.dioInputOptions];
        end
        
        function applyTriggerConfig(obj)
            obj.periodClockIn = obj.hScan.mdfData.resonantSyncInputTerminal;
            dbt = obj.hScan.mdfData.PeriodClockDebounceTime * obj.hAcq.stateMachineLoopRate;
            obj.hFpgaAE.acqParamPeriodTriggerDebounce = round(dbt);
            
            obj.hFpgaAE.acqParamPeriodTriggerMaxPeriod = min(2^16-1,round(1.2*obj.hFpga.nominalAcqLoopRate/obj.hScan.mdfData.nominalResScanFreq));
            
            obj.laserTriggerIn = obj.hScan.mdfData.LaserTriggerPort;
        end
        
        function start(obj)
            tfNS = obj.hScan.trigNextStopEnable && obj.hScan.trigAcqTypeExternal;
            
            if tfNS && ~isempty(obj.nextFileMarkerIn)
                obj.hFpgaAE.acqParamNextTriggerChIdx = obj.hFpga.dioNameToId(obj.nextFileMarkerIn);
            else
                obj.hFpgaAE.acqParamNextTriggerChIdx = 63;
            end
            if tfNS && ~isempty(obj.acqStopTriggerIn)
                obj.hFpgaAE.acqParamStopTriggerChIdx = obj.hFpga.dioNameToId(obj.acqStopTriggerIn);
            else
                obj.hFpgaAE.acqParamStopTriggerChIdx = 63;
            end
            
            if obj.hScan.trigAcqTypeExternal && ~isempty(obj.acqTriggerIn)
                obj.hFpgaAE.acqParamStartTriggerChIdx = obj.hFpga.dioNameToId(obj.acqTriggerIn);
            else
                obj.hFpgaAE.acqParamStartTriggerChIdx = 63;
            end
            
            obj.applyTriggerConfig();
        end
            
        function stop(~)
        end
    end
    
    methods (Hidden)
        function reinitRoutes(obj)
            for i = 1:numel(obj.routes)
                obj.hFpga.setDioOutput(obj.routes{i}{2},obj.routes{i}{1});
            end
            obj.routesEnabled = true;
        end
        
        function deinitRoutes(obj)
            if obj.routesEnabled
                for i = 1:numel(obj.routes)
                    obj.hFpga.setDioOutput(obj.routes{i}{2}, 'Z');
                end
            end
            obj.routesEnabled = false;
        end
        
        function addRoute(obj,signal,dest)
            % make sure there is not already a route using the selected destination
            assert(~any(cellfun(@(rt)strcmp(rt{2},dest),obj.routes)), 'Selected output is already in use.');
            
            % make sure it is a valid signal
            assert(ismember(signal, obj.hFpga.spclOutputSignals), 'Selected signal is not valid.');
            
            % add it to the list
            obj.routes{end+1} = {signal, dest};
            
            % if routes are active, enable it
            if obj.routesEnabled
                obj.hFpga.setDioOutput(dest,signal);
            end
        end
        
        function removeRoute(obj,signal,dest)
            % find it in the list
            id = find(cellfun(@(rt)strcmp(rt{1},signal)&&strcmp(rt{2},dest),obj.routes));
            
            if ~isempty(id)
                if obj.routesEnabled
                    obj.hFpga.setDioOutput(obj.routes{id}{2},'Z');
                end
                obj.routes(id) = [];
            end
        end
    end
    
    %% Property Setter Methods
    methods
        function set.acqTriggerIn(obj,newTerminal)
            if isempty(newTerminal)
                id = 63;
            else
                % make sure terminal is valid
                id = obj.hFpga.dioNameToId(newTerminal);
            end
            
            obj.acqTriggerIn = newTerminal;
            
            if obj.hScan.active && obj.hScan.trigAcqTypeExternal
                obj.hFpgaAE.acqParamStartTriggerChIdx = id;
            end
        end
        
        function set.nextFileMarkerIn(obj,newTerminal)
            if isempty(newTerminal)
                id = 63;
            else
                % make sure terminal is valid
                id = obj.hFpga.dioNameToId(newTerminal);
            end
            
            obj.nextFileMarkerIn = newTerminal;
            
            if obj.hScan.active && obj.hScan.trigNextStopEnable && obj.hScan.trigAcqTypeExternal
                obj.hFpgaAE.acqParamNextTriggerChIdx = id;
            end
        end
        
        function set.acqStopTriggerIn(obj,newTerminal)
            if isempty(newTerminal)
                id = 63;
            else
                % make sure terminal is valid
                id = obj.hFpga.dioNameToId(newTerminal);
            end
            
            obj.acqStopTriggerIn = newTerminal;
            
            if obj.hScan.active && obj.hScan.trigNextStopEnable && obj.hScan.trigAcqTypeExternal
                obj.hFpgaAE.acqParamStopTriggerChIdx = id;
            end
        end
        
        function set.periodClockIn(obj,newTerminal)
            if ~isempty(newTerminal)
                id = obj.hFpga.dioNameToId(newTerminal);
                obj.hFpgaAE.acqParamPeriodTriggerChIdx = id;
            end
            obj.periodClockIn = newTerminal;
        end
        
        function set.laserTriggerIn(obj,newTerminal)
            if isempty(newTerminal)
                id = 63;
            elseif strcmp(newTerminal, 'CLK IN')
                id = 48;
            else
                id = obj.hFpga.dioNameToId(newTerminal);
            end
            
            obj.laserTriggerIn = newTerminal;
        end
        
        function set.auxTrigger1In(obj,newTerminal)
            if isempty(newTerminal)
                id = 63;
            else
                id = obj.hFpga.dioNameToId(newTerminal);
            end
            
            obj.auxTrigger1In = newTerminal;
            obj.hFpgaAE.acqParamAuxTrig1TriggerChIdx = id;
        end
        
        function set.auxTrigger2In(obj,newTerminal)
            if isempty(newTerminal)
                id = 63;
            else
                id = obj.hFpga.dioNameToId(newTerminal);
            end
            
            obj.auxTrigger2In = newTerminal;
            obj.hFpgaAE.acqParamAuxTrig2TriggerChIdx = id;
        end
        
        function set.auxTrigger3In(obj,newTerminal)
            if isempty(newTerminal)
                id = 63;
            else
                id = obj.hFpga.dioNameToId(newTerminal);
            end
            
            obj.auxTrigger3In = newTerminal;
            obj.hFpgaAE.acqParamAuxTrig3TriggerChIdx = id;
        end
        
        function set.auxTrigger4In(obj,newTerminal)
            if isempty(newTerminal)
                id = 63;
            else
                id = obj.hFpga.dioNameToId(newTerminal);
            end
            
            obj.auxTrigger4In = newTerminal;
            obj.hFpgaAE.acqParamAuxTrig4TriggerChIdx = id;
        end
        
        function set.frameClockOut(obj,newTerminal)
            if ~isempty(obj.frameClockOut)
                obj.removeRoute(obj.sliceClkTermInt,obj.frameClockOut);
            end
            obj.frameClockOut = '';
            
            if ~isempty(newTerminal)
                obj.addRoute(obj.sliceClkTermInt, newTerminal);
            end
            obj.frameClockOut = newTerminal;
        end
        
        function set.beamModifiedLineClockOut(obj,newTerminal)
            if ~isempty(obj.beamModifiedLineClockOut)
                obj.removeRoute(obj.beamClkTermInt,obj.beamModifiedLineClockOut);
            end
            obj.beamModifiedLineClockOut = '';
            
            if ~isempty(newTerminal)
                obj.addRoute(obj.beamClkTermInt, newTerminal);
            end
            obj.beamModifiedLineClockOut = newTerminal;
        end
        
        function set.volumeTriggerOut(obj,newTerminal)
            if ~isempty(obj.volumeTriggerOut)
                obj.removeRoute(obj.volumeClkTermInt,obj.volumeTriggerOut);
            end
            obj.volumeTriggerOut = '';
            
            if ~isempty(newTerminal)
                obj.addRoute(obj.volumeClkTermInt, newTerminal);
            end
            obj.volumeTriggerOut = newTerminal;
        end
        
        function set.acqTriggerOnFallingEdge(obj,val)
            validateattributes(val,{'logical'},{'scalar','nonempty'});
            obj.acqTriggerOnFallingEdge = val;
            obj.hFpgaAE.acqParamStartTriggerInvert = val;
        end        
        
        function set.nextFileMarkerOnFallingEdge(obj,val)
            validateattributes(val,{'logical'},{'scalar','nonempty'});
            obj.nextFileMarkerOnFallingEdge = val;
            obj.hFpgaAE.acqParamNextTriggerInvert = val;
        end
        
        function set.acqStopTriggerOnFallingEdge(obj,val)
            validateattributes(val,{'logical'},{'scalar','nonempty'});
            obj.acqStopTriggerOnFallingEdge = val;
            obj.hFpgaAE.acqParamStopTriggerInvert = val;
        end
    end
end


%--------------------------------------------------------------------------%
% Triggering.m                                                             %
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
