classdef GenericPmtController < scanimage.interfaces.PmtController & most.HasMachineDataFile
    %%% ABSTRACT PROPERTY REALIZATIONS (most.HasMachineDataFile)
    properties (Constant, Hidden)
        %Value-Required properties
        mdfClassName = mfilename('class');
        mdfHeading = 'GenericPmtController';
        
        %Value-Optional properties
        mdfDependsOnClasses; %#ok<MCCPI>
        mdfDirectProp;       %#ok<MCCPI>
        mdfPropPrefix;       %#ok<MCCPI>
        
        mdfDefault = defaultMdfSection();
    end
    
    %%% ABSTRACT PROPERTY REALIZATIONS (scanimage.interfaces.PmtController)
    
    %% USER PROPS
    properties (SetAccess = protected)
        hSI;
        numPmts = 0;                % [numerical] number of PMTs managed by the PMT controller
        pmtNames = {};              % Cell array of strings with a short name for each PMT
        pmtInitSuccessful = false;  % Indicates PMT control is ready
        pmtsStatusLastUpdated;      % time of last pmt status update
    end
    
    %% FRIEND PROPS
    properties (Dependent)
        pmtsPowerOn;             % [logical]   array containing power status for each PMT
        pmtsGain;                % [numerical] array containing gain setting for each PMT
        pmtsOffsets;            % [numeric] array containing offset for each PMT
        pmtsBandwidths          % [numeric] array containing amplifier bandwidth for each PMT
    end
    
    properties (Dependent, SetAccess=private)
        pmtsTripped;             % [logical]   array containing trip status for each PMT
    end
    
    properties (Hidden, SetAccess = private)
        hTaskAO = dabs.vidrio.ddi.GenericTask.empty(0,1);
        hTaskDI = dabs.vidrio.ddi.GenericTask.empty(0,1);
        hTaskDO = dabs.vidrio.ddi.GenericTask.empty(0,1);
        hTaskDOTripReset = dabs.vidrio.ddi.GenericTask.empty(0,1);
        
        power_ = nan;
        gain_ = nan;
        tripped_ = nan;
    end
    
    methods 
        function obj = GenericPmtController(hSI)
            obj.hSI = hSI;
            try
                obj.pmtNames = obj.mdfData.pmtNames;
                obj.numPmts = length(obj.pmtNames);
                
                if ischar(obj.mdfData.pmtDaqDeviceName)
                    obj.mdfData.pmtDaqDeviceName = {obj.mdfData.pmtDaqDeviceName};
                end
                
                if length(obj.mdfData.pmtDaqDeviceName) == 1
                    obj.mdfData.pmtDaqDeviceName = repmat(obj.mdfData.pmtDaqDeviceName,1,obj.numPmts);
                end
                
                if obj.numPmts < 1
                    return;
                end
                
                assert(length(obj.mdfData.pmtDaqDeviceName) == obj.numPmts,'PMT controller: length of mdf variable pmtDaqDeviceName does not match length of pmtNames');
                assert(length(obj.mdfData.pmtDaqGainAOChannels) == obj.numPmts,'PMT controller: length of mdf variable pmtDaqGainAOChannels does not match length of pmtNames');
                assert(length(obj.mdfData.pmtDaqTrippedDIChannels) == obj.numPmts,'PMT controller: length of mdf variable pmtDaqTrippedDIChannels does not match length of pmtNames');
                assert(length(obj.mdfData.pmtDaqPowerDOChannels) == obj.numPmts,'PMT controller: length of mdf variable pmtDaqPowerDOChannels does not match length of pmtNames');
                assert(length(obj.mdfData.pmtDaqTripResetDOChannels) == obj.numPmts,'PMT controller: length of mdf variable pmtDaqTripResetDOChannels does not match length of pmtNames');
                assert(length(obj.mdfData.pmtDaqAOVoltageRange) == obj.numPmts,'PMT controller: length of mdf variable pmtDaqAOVoltageRange does not match length of pmtNames');
                assert(length(obj.mdfData.pmtMaxGainValue) == obj.numPmts,'PMT controller: length of mdf variable pmtMaxGainValue does not match length of pmtNames');
                    
                for idx = 1:obj.numPmts
                    dev = obj.hSI.initIfVdaq(obj.mdfData.pmtDaqDeviceName{idx});
                    
                    obj.hTaskAO(idx) = dabs.vidrio.ddi.AoTask(dev, sprintf('GenericPmtController AO Gain %d',idx));
                    if ~isnan(obj.mdfData.pmtDaqGainAOChannels(idx))
                        obj.hTaskAO(idx).addChannel(obj.mdfData.pmtDaqGainAOChannels(idx),obj.pmtNames{idx});
                        obj.hTaskAO(idx).unreserveResource();
                    end
                    
                    obj.hTaskDO(idx) = dabs.vidrio.ddi.DoTask(dev, sprintf('GenericPmtController DO Power %d',idx));
                    if ~isempty(obj.mdfData.pmtDaqPowerDOChannels{idx})
                        obj.mdfData.pmtDaqPowerDOChannels{idx} = formatDigitalPortString(obj.mdfData.pmtDaqPowerDOChannels{idx});
                        obj.hTaskDO(idx).addChannel(obj.mdfData.pmtDaqPowerDOChannels{idx},obj.pmtNames{idx});
                        obj.hTaskDO(idx).unreserveResource();
                    end
                    
                    obj.hTaskDI(idx) = dabs.vidrio.ddi.DiTask(dev, sprintf('GenericPmtController DI Trip Detect %d',idx));
                    if ~isempty(obj.mdfData.pmtDaqTrippedDIChannels{idx})
                        obj.mdfData.pmtDaqTrippedDIChannels{idx} = formatDigitalPortString(obj.mdfData.pmtDaqTrippedDIChannels{idx});
                        obj.hTaskDI(idx).addChannel(obj.mdfData.pmtDaqTrippedDIChannels{idx},obj.pmtNames{idx});
                        obj.hTaskDI(idx).unreserveResource();
                    end
                    
                    obj.hTaskDOTripReset(idx) = dabs.vidrio.ddi.DoTask(dev, sprintf('GenericPmtController DO Trip Reset %d',idx));
                    if ~isempty(obj.mdfData.pmtDaqTripResetDOChannels{idx})
                        obj.mdfData.pmtDaqTripResetDOChannels{idx} = formatDigitalPortString(obj.mdfData.pmtDaqTripResetDOChannels{idx});
                        obj.hTaskDOTripReset(idx).addChannel(obj.mdfData.pmtDaqTripResetDOChannels{idx},obj.pmtNames{idx});
                        obj.hTaskDOTripReset(idx).unreserveResource();
                    end
                end
                
                if length(obj.mdfData.pmtDaqAOVoltageRange) == 1
                    obj.mdfData.pmtDaqAOVoltageRange = repmat(obj.mdfData.pmtDaqAOVoltageRange,1,obj.numPmts);
                end
                
                if length(obj.mdfData.pmtMaxGainValue) == 1
                    obj.mdfData.pmtMaxGainValue = repmat(obj.mdfData.pmtMaxGainValue,1,obj.numPmts);
                end
                
                obj.power_ = false(1,obj.numPmts);
                obj.gain_ = nan(1,obj.numPmts);
                obj.tripped_ = false(1,obj.numPmts);
                
                obj.pmtInitSuccessful = true;
                obj.updateOutputs();
                obj.notify('pmtStatusChanged');
            catch ME
                fprintf(2,'Error initializing GenericPmtController PMTs\n');
                most.ErrorHandler.logAndReportError(ME);
                delete(obj);                
            end
            
            function str = formatDigitalPortString(str)
                if ~regexpi(str,'PFI')
                    str = scanimage.util.translateTriggerToPort(str);
                end
            end
        end
        
        function delete(obj)
            try
                if obj.pmtInitSuccessful
                    obj.pmtsPowerOn = false(1,obj.numPmts);
                    obj.pmtsGain    = zeros(1,obj.numPmts);
                end
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
            most.idioms.safeDeleteObj(obj.hTaskAO);
            most.idioms.safeDeleteObj(obj.hTaskDI);
            most.idioms.safeDeleteObj(obj.hTaskDO);
            most.idioms.safeDeleteObj(obj.hTaskDOTripReset);            
        end
    end
    
    % setter/getter methods
    methods
        function set.pmtsPowerOn(obj,val)
            validateattributes(val,{'logical','numeric'},{'vector','numel',obj.numPmts});
            
            chg = any(val ~= obj.power_);
            obj.power_ = logical(val(:)');
            
            if obj.pmtInitSuccessful
                obj.updateOutputs();
                
                if chg
                    obj.notify('pmtStatusChanged');
                end
            end
        end
        
        function val = get.pmtsPowerOn(obj)
            val = obj.power_;
        end
        
        function set.pmtsGain(obj,val)
            validateattributes(val,{'numeric'},{'vector','numel',obj.numPmts,'nonnegative'});
            
            chg = any(val ~= obj.gain_);
            obj.gain_ = max(min(val(:)',obj.mdfData.pmtMaxGainValue),0);
            
            if obj.pmtInitSuccessful
                if isempty(obj.hTaskAO)
                    obj.gain_ = nan(1,obj.numPmts);
                end
                
                obj.updateOutputs();
                if chg
                    obj.notify('pmtStatusChanged');
                end
            end
        end
        
        function val = get.pmtsGain(obj)
            val = obj.gain_;
        end
        
        function val = get.pmtsTripped(obj)
            if isempty(obj.hTaskDI)
                val = false(1,obj.numPmts);
            else
                val = arrayfun(@(h)h.readChannelInputValues(),obj.hTaskDI);
                val = val(:)';
                obj.pmtsStatusLastUpdated = tic;
                
                if any(val ~= obj.tripped_)
                    obj.tripped_ = val;
                    obj.notify('pmtStatusChanged');
                end
            end
        end
        
        function set.pmtsOffsets(obj,val)
            % No-Op
        end
        
        function val = get.pmtsOffsets(obj)
            val = nan(1,obj.numPmts);
        end
        
        function set.pmtsBandwidths(obj,val)
            % No-Op
        end
        
        function val = get.pmtsBandwidths(obj)
            val = nan(1,obj.numPmts);
        end
        
        function updateOutputs(obj)
            voltagerange = vertcat(obj.mdfData.pmtDaqAOVoltageRange{:})';
            ao = obj.pmtsGain .* diff(voltagerange,1) ./ obj.mdfData.pmtMaxGainValue + voltagerange(1,:);
            ao = ao .* obj.pmtsPowerOn;
            
            % Fix for single enable analog pmt controller i.e. Janelia
            % Controller.
%             pmtsOn = obj.pmobj.pmtsPowerOn;
%             pmtsOn(:) = any(pmtsOn);
%             obj.hTaskDO.writeDigitalData(logical(pmtsOn));

            % Comment out the following line if using the above fix
            % above code needs update
            
            for i = 1:obj.numPmts
                if ~isempty(obj.hTaskAO(i).channels)
                    obj.hTaskAO(i).setChannelOutputValues(ao(i));
                end
                
                if ~isempty(obj.hTaskDO(i).channels)
                    obj.hTaskDO(i).setChannelOutputValues(logical(obj.pmtsPowerOn(i)));
                end
            end
        end
    end
    
    %% USER METHODS
    methods
        function resetPmtTripStatus(obj,pmtNum)
            if ~isempty(obj.hTaskDOTripReset(pmtNum).channels)
                obj.hTaskDOTripReset(pmtNum).setChannelOutputValues(1);
                pause(0.25);
                obj.hTaskDOTripReset(pmtNum).setChannelOutputValues(0);
            else
                % perform a soft reset by powercycling the PMT
                pw = obj.pmtsPowerOn(pmtNum);
                
                if ~isempty(obj.hTaskDO(pmtNum).channels)
                    obj.hTaskDO(pmtNum).setChannelOutputValues(0);
                elseif ~isempty(obj.hTaskAO(pmtNum).channels)
                    obj.hTaskDO(pmtNum).setChannelOutputValues(0);
                end
                
                if pw
                    pause(0.25);
                    obj.updateOutputs();
                end
            end
        end
        
        function [powerOn, gain, tripped, offsets, bandwidths] = getLastPmtStatus(obj)
            powerOn = obj.power_;
            gain = obj.gain_;
            tripped = obj.tripped_;
            offsets = nan(1,obj.numPmts);
            bandwidths = nan(1,obj.numPmts);
        end
        
        function setPmtPower(obj, pmtNum, val)
            obj.pmtsPowerOn(pmtNum) = val;
        end
        
        function setPmtGain(obj, pmtNum, val)
            obj.pmtsGain(pmtNum) = val;
        end
        
        function setPmtOffset(~, ~, ~)
            % no op
        end
        
        function setPmtBandwidth(~, ~, ~)
            % no op
        end
        
        function updatePmtsStatus(obj)
            [~] = obj.pmtsTripped; %causes an update and event to be fired if there is a change
        end
    end
end
 
function s = defaultMdfSection()
    s = [...
        makeEntry('pmtNames',{{'Green' 'Red'}},'cell array of names for PMTs e.g.')...
        makeEntry()... % blank line
        makeEntry('pmtDaqDeviceName',{{'Dev1' 'Dev1'}},'cell array of vDAQ or NI-DAQ devices to control each PMT channel. If only one device is given, all channels will be mapped onto that one device')...
        makeEntry('pmtDaqGainAOChannels',[0 1],'<optional> array of numeric analog output channel IDs to control the gain for each PMT; if set to empty array, functionality is disabled')...
        makeEntry('pmtDaqPowerDOChannels',{{'port0/line0' 'port0/line3'}},'<optional> cell array of strings specifying the digital port name to switch each PMT on/off; if set to empty cell array, functionality is disabled')...
        makeEntry('pmtDaqTrippedDIChannels',{{'port0/line1' 'port0/line4'}},'<optional> cell array of strings specifying the digital port name to detect the trip status for each PMT; if set to empty cell array, functionality is disabled')...
        makeEntry('pmtDaqTripResetDOChannels',{{'port0/line2' 'port0/line5'}},'<optional> cell array of strings specifying the digital port name to reset the trip status for each PMT; if set to empty cell array, functionality is disabled')...
        makeEntry()... % blank line
        makeEntry('pmtDaqAOVoltageRange',{{[0 5],[0 5]}},'<required if pmtDaqGainAOChannels is defined> cell array of 1x2 numeric array specifying the minimum and maximum analog output voltage on the NI-DAQ board that controls the PMT gain. If only one numeric array is given, this value is used for all PMT channels')...
        makeEntry('pmtMaxGainValue',[1250 1250],'<required if pmtDaqGainAOChannels is defined> array specifying the maximum display value for the PMT gain. If only one value is given, this value is used for all PMT channels')...
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
% GenericPmtController.m                                                   %
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
