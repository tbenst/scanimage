classdef WaveformManager < scanimage.interfaces.Component
    % WaveformManager     Functionality to manage and optimize output waveforms

    %%% User Props
    properties (SetObservable, SetAccess = protected, Transient)
        scannerAO = struct();   % Struct containing command waveforms for scanners
    end
    
    properties (Dependent, Transient)
        optimizedScanners;      % Cell array of strings, indicating the scanners for which optimized waveforms are available
    end
    
    properties (SetAccess = immutable, Hidden)
        waveformCacheBasePath;
    end
    
    %%% ABSTRACT PROPERTY REALIZATION (most.Model)
    properties (Hidden, SetAccess=protected)
        mdlPropAttributes = ziniInitPropAttributes();
        mdlHeaderExcludeProps = {'scannerAO'};
    end
    
    %%% ABSTRACT PROPERTY REALIZATION (scanimage.interfaces.Component)
    properties (SetAccess = protected, Hidden)
        numInstances = 1;
    end
    
    properties (Constant, Hidden)
        COMPONENT_NAME = 'WaveformManager'                  % [char array] short name describing functionality of component e.g. 'Beams' or 'FastZ'
        PROP_TRUE_LIVE_UPDATE = {};                         % Cell array of strings specifying properties that can be set while the component is active
        PROP_FOCUS_TRUE_LIVE_UPDATE = {} ;                  % Cell array of strings specifying properties that can be set while focusing
        DENY_PROP_LIVE_UPDATE = {};                         % Cell array of strings specifying properties for which a live update is denied (during acqState = Focus)
        
        FUNC_TRUE_LIVE_EXECUTION = {};                      % Cell array of strings specifying functions that can be executed while the component is active
        FUNC_FOCUS_TRUE_LIVE_EXECUTION = {};                % Cell array of strings specifying functions that can be executed while focusing
        DENY_FUNC_LIVE_EXECUTION = {'calibrateScanner'};                      % Cell array of strings specifying functions for which a live execution is denied (during acqState = Focus)
    end
    
    %% LIFECYCLE
    methods
        function obj = WaveformManager(hSI) 
            obj = obj@scanimage.interfaces.Component(hSI);
            obj.waveformCacheBasePath = fullfile(obj.hSI.classDataDir, sprintf('Waveforms_Cache'));
        end
        
        function delete(obj)
            % No-op
        end
    end
    
    methods (Access=protected, Hidden)
        function mdlInitialize(obj)
            mdlInitialize@scanimage.interfaces.Component(obj);
        end
    end
    
    %% INTERNAL METHODS
    methods (Access = protected, Hidden)
        function componentStart(obj)
        end
        
        function componentAbort(obj)
        end
    end
    
        
    %% Getter/Setter Methods
    methods
        function val = get.scannerAO(obj)
            obj.scannerAO = obj.updateWaveformsMotionCorrection(obj.scannerAO);
            val = obj.scannerAO;
        end
        
        function val = get.optimizedScanners(obj)
            val = {};
            if isfield(obj.scannerAO,'ao_volts') && isfield(obj.scannerAO.ao_volts,'isOptimized')
                fieldnames_ = fieldnames(obj.scannerAO.ao_volts.isOptimized);
                tf = cellfun(@(fn)obj.scannerAO.ao_volts.isOptimized.(fn),fieldnames_);
                val = fieldnames_(tf);
            end
        end
    end
    
    %% USER METHODS
    methods
        function updateWaveforms(obj,forceOptimizationCheck)
            % function to regenerate command waveforms for scanner control
            % automatically checks waveform cache for optimized waveforms
            % waveforms are stored in hSI.hWaveformManger.scannerAO
            %
            % usage:
            %     hSI.hWaveformManager.updateWaveforms()
            %     hSI.hWaveformManager.updateWaveforms(true)  % checks waveform cache even if command waveform has not changed since last call
            obj.hSI.hStackManager.updateZSeries();
            
            if nargin < 2 || isempty(forceOptimizationCheck)
                forceOptimizationCheck = false;
            end
            
            % generate planes to scan based on motor position etc
            rg = obj.hSI.hScan2D.currentRoiGroup;
            ss = obj.hSI.hScan2D.scannerset;
            sliceScanTime = [];
            if obj.hSI.hStackManager.isFastZ
                zPowerReference = obj.hSI.hStackManager.zPowerReference;
                zs = obj.hSI.hStackManager.zs;
                zsRelative = obj.hSI.hStackManager.zsRelative;
                flybackFrames = obj.hSI.hFastZ.numDiscardFlybackFrames;
                waveform = obj.hSI.hFastZ.waveformType;
                zActuator = 'fast';
            elseif obj.hSI.hStackManager.isSlowZ
                zPowerReference = obj.hSI.hStackManager.zPowerReference;
                currentSlc = obj.hSI.hStackManager.slicesDone*obj.hSI.hStackManager.framesPerSlice + obj.hSI.hStackManager.framesDone;
                nextSlc = currentSlc + 1;
                nextSlc = mod(nextSlc-1,numel(obj.hSI.hStackManager.zs))+1;
                zs = obj.hSI.hStackManager.zs(nextSlc);
                zsRelative = obj.hSI.hStackManager.zsRelative(nextSlc);
                flybackFrames = 0;
                
                waveform = 'slow';
                switch obj.hSI.hStackManager.stackActuator
                    case scanimage.types.StackActuator.fastZ
                        zActuator = 'fast';
                    case scanimage.types.StackActuator.motor
                        zActuator = 'slow';
                    otherwise
                        error('Unknown z actuator: %s',obj.hSI.hStackManager.stackActuator);
                end
                if nextSlc == 1
                    sliceScanTime = max(arrayfun(@(z)rg.sliceTime(ss,z),obj.hSI.hStackManager.zs));
                else
                    sliceScanTime =  obj.scannerAO.sliceScanTime;
                end
            else
                zPowerReference = obj.hSI.hStackManager.zPowerReference;
                zs = obj.hSI.hStackManager.zs;
                zsRelative = obj.hSI.hStackManager.zsRelative;
                
                flybackFrames = 0;
                waveform = '';
                zActuator = '';
            end
            
            % generate ao using scannerset
            [ao_volts_raw, ao_samplesPerTrigger, sliceScanTime, pathFOV] = ...
                rg.scanStackAO(ss,zPowerReference,zs,zsRelative,waveform,flybackFrames,zActuator,sliceScanTime,[]);

            sampleRates = struct();
            
            if isfield(ao_volts_raw,'G')
                assert(size(ao_volts_raw(1).G,1) > 0, 'Generated AO is empty. Ensure that there are active ROIs with scanfields that exist in the current Z series.');
                sampleRates.G = ss.scanners{1}.sampleRateHz;
            end

            if isfield(ao_volts_raw,'B')
                sampleRates.B = ss.beams.sampleRateHz;
            end

            if isfield(ao_volts_raw,'Z')
                sampleRates.Z = ss.fastz.sampleRateHz;
            end
            
            
            if ~forceOptimizationCheck && ...
               isfield(obj.scannerAO,'ao_volts_raw') && isequal(obj.scannerAO.ao_volts_raw,ao_volts_raw) && ...
               isfield(obj.scannerAO,'ao_samplesPerTrigger') && isequal(obj.scannerAO.ao_samplesPerTrigger,ao_samplesPerTrigger) && ...
               isfield(obj.scannerAO,'sliceScanTime') && isequal(obj.scannerAO.sliceScanTime,sliceScanTime) && ...
               isfield(obj.scannerAO,'pathFOV') && isequal(obj.scannerAO.pathFOV,pathFOV) && ...
               isfield(obj.scannerAO,'sampleRate') && isequal(obj.scannerAO.sampleRate,sampleRates)
                % the newly generated AO is the same as the previous one.
                % no further action required
                return
            else
                %%% check for optimized versions of waveform
                allScanners = fieldnames(ao_volts_raw);
                
                % initialize isOptimized struct
                isOptimized = struct();
                for idx = 1:length(allScanners)
                    isOptimized.(allScanners{idx}) = false;
                end
                
                ao_volts = ao_volts_raw;
                optimizableScanners = intersect(allScanners,ss.optimizableScanners);
                for idx = 1:length(optimizableScanners)
                    scanner = optimizableScanners{idx};
                    waveform = [];
                    if ~isempty(waveform)
                        ao_volts.(scanner) = waveform;
                        isOptimized.(scanner) = true;
                    end
                end
            end
            
            scannerAO_ = struct();
            scannerAO_.ao_volts_raw         = ao_volts_raw;
            scannerAO_.ao_volts             = ao_volts;
            scannerAO_.ao_volts.isOptimized = isOptimized;
            scannerAO_.ao_samplesPerTrigger = ao_samplesPerTrigger;
            scannerAO_.sliceScanTime        = sliceScanTime;
            scannerAO_.pathFOV              = pathFOV;
            scannerAO_.sampleRates           = sampleRates;
            
            obj.scannerAO = scannerAO_;
        end
        
        function scannerAO = updateWaveformsMotionCorrection(obj,scannerAO)
            if isempty(scannerAO)
                return
            end
            
            if isempty(obj.hSI.hMotionManager.scannerOffsets)
                scannerAO = obj.clearWaveformsMotionCorrection(scannerAO);
            else
                offsetvolts = obj.hSI.hMotionManager.scannerOffsets.ao_volts;
                scanners = fieldnames(offsetvolts);
                
                for idx = 1:length(scanners)
                    scanner = scanners{idx};
                    if ~isfield(scannerAO.ao_volts,scanner)
                        most.idioms.warn('Scanner ''%s'' waveform could not be updated for motion correction',scanner);
                        continue
                    end
                    
                    if ~isfield(scannerAO,'ao_volts_beforeMotionCorrection') || ...
                       ~isfield(scannerAO.ao_volts_beforeMotionCorrection,scanner)
                        scannerAO.ao_volts_beforeMotionCorrection.(scanner) = scannerAO.ao_volts.(scanner);
                        scannerAO.ao_volts_correction.(scanner) = zeros(1,size(scannerAO.ao_volts.(scanner),2));
                    end
                    if ~isequal(offsetvolts.(scanner),scannerAO.ao_volts_correction.(scanner))
                        scannerAO.ao_volts.(scanner) = bsxfun(@plus,scannerAO.ao_volts_beforeMotionCorrection.(scanner),offsetvolts.(scanner));
                        scannerAO.ao_volts_correction.(scanner) = offsetvolts.(scanner);
                    end
                end
            end            
        end
        
        function scannerAO = clearWaveformsMotionCorrection(obj,scannerAO)
            if isempty(scannerAO)
                return
            end
            
            if isfield(scannerAO,'ao_volts_beforeMotionCorrection')
                scanners = fieldnames(scannerAO.ao_volts_beforeMotionCorrection);
                for idx = 1:length(scanners)
                    scanner = scanners{idx};
                    scannerAO.ao_volts.(scanner) = scannerAO.ao_volts_beforeMotionCorrection.(scanner);
                end
                scannerAO = rmfield(scannerAO,'ao_volts_beforeMotionCorrection');
                scannerAO = rmfield(scannerAO,'ao_volts_correction');
            end
        end
        
        function resetWaveforms(obj)
            % function to clear hSI.hWaveformManager.scannerAO
            %
            % usage:
            %   hSI.hWaveformManager.resetWaveforms()
            obj.scannerAO = [];
        end
        
        function calibrateScanner(obj,scanner)
            % function to calibrate scanner feedback and offset
            %
            % usage:
            %   hSI.hWaveformManager.calibrateScanner('<scannerName>')
            %       where <scannerName> is one of {'G','Z'}
            if obj.componentExecuteFunction('calibrateScanner',scanner)
                msg = 'Calibrating Scanner';
                hWb = waitbar(0,msg,'CreateCancelBtn',@(src,evt)delete(ancestor(src,'figure')));
                hTitle = findall(hWb,'String',msg);
                set(hTitle,'Interpreter','none');
                try
                    ss = obj.hSI.hScan2D.scannerset;    % Used as the base to reference particular scanners.
                    ss.calibrateScanner(scanner,hWb);
                catch ME
                    hWb.delete();
                    rethrow(ME);
                end
                hWb.delete();
            end
        end
        
        function plotWaveforms(obj,scanner)
            % function to plot scanner command waveform for specified scanner
            %
            % usage:
            %   hSI.hWaveformManager.plotWaveforms('<scannerName>')
            %       where <scannerName> is one of {'G','Z'}
            
            % ensure waveforms are up to date
            obj.updateWaveforms();
            
            assert(~isempty(obj.scannerAO) && isfield(obj.scannerAO,'ao_volts'),'scannerAO is empty');
            assert(isfield(obj.scannerAO.ao_volts,scanner),'scannerAO is empty');
            
            hFig = figure('NumberTitle','off','Name','Waveform Output');
            if obj.scannerAO.ao_volts.isOptimized.(scanner)
                error('This functionality is only available in the premium ScanImage version');
            else
                hAx = axes('Parent',hFig,'XGrid','on','YGrid','on','Box','on');
                
                if strcmpi(scanner,'SLMxyz')
                    xy = obj.scannerAO.ao_volts.(scanner);
                    plot(hAx,xy(:,1),xy(:,2),'*-');
                    title(hAx,'SLM Output');
                    hAx.YDir = 'reverse';
                    hAx.DataAspectRatio = [1 1 1];
                    xlabel(hAx,'x');
                    ylabel(hAx,'y');
                    grid(hAx,'on');
                else
                    plot(hAx,obj.scannerAO.ao_volts.(scanner));
                    title(hAx,'Waveform Output');
                    xlabel(hAx,'Samples');
                    ylabel(hAx,'Volts');
                    grid(hAx,'on');
                end
            end
            
        end
    end
    
end

%% LOCAL (after classdef)
function s = ziniInitPropAttributes()
s = struct();
end


%--------------------------------------------------------------------------%
% WaveformManager.m                                                        %
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
