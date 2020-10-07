classdef CoordinateSystems < scanimage.interfaces.Component & most.HasClassDataFile 
    %% USER PROPS    
    properties (SetAccess = private)
        hCSWorld;     % root coordinate system for ScanImage
        hCSReference; % root coordinate system for ScanImage. origin of Reference is the focal point of the objective, when FastZ is set to zero
        hCSFocus;     % focus point after taking FastZ defocus into account
    end
    
    properties (Dependent, SetAccess = private)
        hCSStageAbsolute
        hCSSampleAbsolute
        hCSStageRelative
        hCSSampleRelative
    end
    
    properties (SetAccess = private, GetAccess = private)
        hListeners = event.listener.empty(1,0);
    end
    
    %% INTERNAL PROPS
    %%% ABSTRACT PROPERTY REALIZATION (most.Model)
    properties (Hidden, SetAccess=protected)
        mdlPropAttributes = ziniInitPropAttributes();
        mdlHeaderExcludeProps = {};
    end
    
    %%% ABSTRACT PROPERTY REALIZATION (scanimage.interfaces.Component)
    properties (SetAccess = protected, Hidden)
        numInstances = 1;
    end
    
    properties (Constant, Hidden)
        COMPONENT_NAME = 'CoordinateSystems';               % [char array] short name describing functionality of component e.g. 'Beams' or 'FastZ'
        PROP_TRUE_LIVE_UPDATE = {};                         % Cell array of strings specifying properties that can be set while the component is active
        PROP_FOCUS_TRUE_LIVE_UPDATE = {};                   % Cell array of strings specifying properties that can be set while focusing
        DENY_PROP_LIVE_UPDATE = {};                         % Cell array of strings specifying properties for which a live update is denied (during acqState = Focus)
        
        FUNC_TRUE_LIVE_EXECUTION = {};                      % Cell array of strings specifying functions that can be executed while the component is active
        FUNC_FOCUS_TRUE_LIVE_EXECUTION = {};                % Cell array of strings specifying functions that can be executed while focusing
        DENY_FUNC_LIVE_EXECUTION = {};                      % Cell array of strings specifying functions for which a live execution is denied (during acqState = Focus)
    end
    
    properties (Hidden, SetAccess=?scanimage.interfaces.Class, SetObservable)
        classDataFileName;
    end
    
    %% LIFECYCLE
    methods
        function obj = CoordinateSystems(hSI)
            obj = obj@scanimage.interfaces.Component(hSI);
            
            % Determine classDataFile name and path
            if isempty(obj.hSI.classDataDir)
                pth = most.util.className(class(obj),'classPrivatePath');
            else
                pth = obj.hSI.classDataDir;
            end
            classNameShort = most.util.className(class(obj),'classNameShort');
            obj.classDataFileName = fullfile(pth, [classNameShort '_classData.mat']);
            
            obj.hCSWorld = scanimage.mroi.coordinates.CSLinear('World',3);
            obj.hCSReference = scanimage.mroi.coordinates.CSLinear('Reference space',3,obj.hCSWorld);
            obj.hCSFocus = scanimage.mroi.coordinates.CSLinear('Focus',3,obj.hCSReference);
            obj.hCSFocus.lock = true; % do not load from class data file
            
            obj.hListeners = most.ErrorHandler.addCatchingListener(obj.hSI,'imagingSystem','PostSet',@(varargin)obj.updateCSFocus);
        end
        
        function delete(obj)
            % coordinate systems will automatically be deleted once they go
            % out of reference
            
            most.idioms.safeDeleteObj(obj.hListeners);
            obj.save();
        end
    end
    
    %% Abstract methods realizations (scanimage.interfaces.Component)
    methods (Access = protected, Hidden)
        function mdlInitialize(obj)
            mdlInitialize@most.Model(obj);
            obj.loadClassData();
        end
        
        function componentStart(obj,varargin)
        end
        
        function componentAbort(obj,varargin)
        end
    end
    
    %% Class methods
    methods
        function plot(obj)
            %PLOT plot ScanImages' coordinate system tree
            %   
            %   Opens a window that visualizes ScanImage's internal
            %   coordinate system structure

            obj.hCSWorld.plotTree();
        end
             
        function reset(obj)
            %RESET resets all coordinate systems derived from 'World'
            %   
            %   Retrieves the coordinate system tree and resets all nodes
            %   with their respective reset function
            
            [~,nodes] = obj.hCSWorld.getTree();
            cellfun(@(n)n.reset(), nodes);
        end
        
        function load(obj)
            %LOAD loads the coordinate system definitions from disk
            %
            %   Loads the coordinate system settings from the class data
            %   file
            
            obj.loadClassData();
        end
        
        function save(obj)
            %SAVE saves the coordinate system definitions to disk
            %
            %   Saves the coordinate system settings to the class data
            %   file. this function is automatically executed when
            %   ScanImage is exited
            
            obj.saveClassData();
        end
    end
    
    %% Saving / Loading
    methods (Hidden)
        function s = toStruct(obj)
            [~,nodes] = obj.hCSWorld.getTree();
            nodeStructs  = cellfun(@(n)n.toStruct, nodes, 'UniformOutput', false);
            s = nodeStructs;
        end
        
        function fromStruct(obj,s)
            [~,nodes] = obj.hCSWorld.getTree();
            nodeNames  = cellfun(@(n)n.name, nodes, 'UniformOutput', false);
            
            for idx = 1:numel(s)
                try
                    nodeStruct = s{idx};
                    mask = strcmp(nodeStruct.name__,nodeNames);
                    
                    if ~any(mask)
                        %warning('Coordinate system %s on disk does not exist in ScanImage''s coordinate system tree.',nodeStruct.name__);
                    else
                        node = nodes{mask};
                        if isempty(node)
                            warning('Could not load coordinate system %s',nodeStruct.name__);
                        else
                            node.fromStruct(nodeStruct);
                        end
                    end
                catch ME
                    most.ErrorHandler.logAndReportError(ME);
                end
            end
        end
    
        function ensureClassDataFileProps(obj)
            obj.ensureClassDataFile(struct('CoordinateSystemConfigs',[]),obj.classDataFileName);
        end
        
        function loadClassData(obj)
            obj.ensureClassDataFileProps();
            s = obj.getClassDataVar('CoordinateSystemConfigs',obj.classDataFileName);
            obj.fromStruct(s);
        end
        
        function saveClassData(obj)
            if ~obj.mdlInitialized
                return % this is to prevent saving the default coordinate systems if startup fails before we executed obj.loadClassData 
            end
            
            try
                obj.ensureClassDataFileProps();
                
                s = obj.toStruct();
                obj.setClassDataVar('CoordinateSystemConfigs',s,obj.classDataFileName);
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
        end
    end
    
    %% Internal Methods
    methods (Hidden)
        function updateCSFocus(obj)
            z = obj.hSI.hFastZ.positionTarget;
            
            T = eye(4);
            T(3,4) = z;
            
            obj.hCSFocus.toParentAffine = T;
        end
    end
    
    %% Property Getter/Setter    
    methods
        function val = get.hCSStageAbsolute(obj)
            val = obj.hSI.hMotors.hCSStageAbsolute;
        end
        
        function val = get.hCSSampleAbsolute(obj)
            val = obj.hSI.hMotors.hCSSampleAbsolute;
        end
        
        function val = get.hCSStageRelative(obj)
            val = obj.hSI.hMotors.hCSStageRelative;
        end
        
        function val = get.hCSSampleRelative(obj)
            val = obj.hSI.hMotors.hCSSampleRelative;
        end
    end
end

%% LOCAL (after classdef)
function s = ziniInitPropAttributes()
s = struct();
end

%--------------------------------------------------------------------------%
% CoordinateSystems.m                                                      %
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
