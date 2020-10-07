classdef SIPage < scanimage.guis.configuration.ConfigurationPage
    
    properties
        hObjectiveResolutionText;
        hObjectiveResolutionEdit;
        hAddlComponentsTable;
        hSimulatedModeCheckBox;
        hCustStartupScrEdit;
        
        simulated;
        hasThorECU;
        hasBScope2;
        hasPMTController;
        
        delChar = ['<html><table border=0 width=50><TR><TD><center>' char(10007) '</center></TD></TR></table></html>'];
        keyDown = false;
    end
    
    properties (SetObservable)
        customComponents = {};
        startupScript = '';
        
        knownComponents = {'Thorlabs ECU 1' 'Thorlabs B-Scope 2' 'Analog PMT Controller' 'Bruker Resonant Controller'};
        knownComponentMapping = {'dabs.thorlabs.ECU1' 'dabs.thorlabs.BScope2' 'dabs.generic.GenericPmtController' 'dabs.bruker.BrukerResonantControl'};
    end
    
    properties (Constant)
        modelClass = 'scanimage.SI';
    end
    
    methods
        function obj = SIPage(hConfigEditor, create)
            if nargin < 2 || isempty(create)
                create = false;
            end
            obj = obj@scanimage.guis.configuration.ConfigurationPage(hConfigEditor,create);
            
            obj.listLabel = 'General ScanImage Settings';
            obj.heading = 'ScanImage';
            obj.descriptionText = ['Welcome to ScanImage! Microscope configuration options are divided into sections accessible from the selection on the left. This section allows you to specify '...
                                    'a custom script to execute on ScanImage startup and add custom plugin modules to extend ScanImage functionality.'];
            
            % create form layout
            ph = 480;
            obj.hPanel = uipanel('parent',[],'BorderType','none','units','pixels','position',[0 0 400 ph]);
            
            p = uipanel('parent',obj.hPanel,'units','pixels','position',[20 ph-80 400 70],'bordertype','none');
            l = scanimage.util.ScanImageLogo(p,false);
            l.progress = 1;
            l.backgroundColor = .94*ones(1,3);
            l.color = .25*ones(1,3);
            
            uicontrol(...
                'parent', obj.hPanel, ...
                'Style', 'text', ...
                'String', ['Version ' scanimage.SI.VERSION_MAJOR '.' scanimage.SI.VERSION_MINOR], ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Fontweight','bold',...
                'Fontsize',10,...
                'Position', [46 ph-115 600 16]);
            
            uicontrol(...
                'parent', obj.hPanel, ...
                'Style', 'text', ...
                'String', 'Custom Startup Script', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [46 ph-160 265 14]);
            
            obj.hCustStartupScrEdit = most.gui.uicontrol(...
                'parent', obj.hPanel, ...
                'Style', 'edit', ...
                'String', '', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [226 ph-164 200 22],...
                'Bindings',{obj 'startupScript' 'string'});
            
            uicontrol(...
                'parent', obj.hPanel, ...
                'String', 'Create/Edit', ...
                'HorizontalAlignment', 'center', ...
                'Units', 'pixels', ...
                'Position', [434 ph-164 80 22],...
                'callback',@obj.editScr);
            
            uicontrol(...
                'parent', obj.hPanel, ...
                'Style', 'text', ...
                'String', 'Plugins and Custom Components', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [46 ph-220 265 14]);
            
            % Additional Components Table
            addlComponentsColumnNames      = {'Plugin/Component Name' 'Delete'};
            addlComponentsColumnFormats    = {[obj.knownComponents {'Custom...'}] 'char'};
            addlComponentsColumnEditable   = [true, false];
            addlComponentsColumnWidths     = {250 50};
            addlComponentsBlankRow         = {'' obj.delChar};
            
            obj.hAddlComponentsTable = uitable( ... 
                'parent', obj.hPanel, ...
                'Tag', 'addlComponentsTable', ...
                'Data', addlComponentsBlankRow, ...
                'ColumnName', addlComponentsColumnNames, ...
                'ColumnFormat', addlComponentsColumnFormats, ...
                'ColumnEditable', addlComponentsColumnEditable, ...
                'ColumnWidth', addlComponentsColumnWidths, ...
                'RowName', [], ...
                'RowStriping', 'Off', ...
                'Units', 'pixels', ...
                'Position', [46 ph-322 322 96],...
                'KeyPressFcn',@obj.KeyFcn,...
                'KeyReleaseFcn',@obj.KeyFcn,...
                'CellSelectionCallback',@obj.compCellSelFcn,...
                'CellEditCallback',@obj.compCellEditFcn);
            
            uicontrol(...
                'parent', obj.hPanel, ...
                'Style', 'text', ...
                'String', 'Enter the conversion factor from scan mirror angles to scan size in units of microns per scan angle. This value can be calculated or measured later using a stage.', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Fontsize',10,...
                'Position', [46 ph-390 600 32]);
            
            % ObjectiveResolutionText
            obj.hObjectiveResolutionText = uicontrol(...
                'parent', obj.hPanel, ...
                'Tag', 'ObjectiveResolutionText', ...
                'Style', 'text', ...
                'String', 'Scan Angle Resolution (um/deg)', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [46 ph-415 265 14]);
        
            % ObjectiveResolutionEdit 
            obj.hObjectiveResolutionEdit = uicontrol(...
                'parent', obj.hPanel, ...
                'Tag', 'ObjectiveResolutionEdit', ...
                'Style', 'edit', ...
                'String', '15', ...
                'HorizontalAlignment', 'center', ...
                'Units', 'pixels', ...
                'Position', [226 ph-419 51 22]);
            
            % SimulatedModeCheckBox
            obj.hSimulatedModeCheckBox = uicontrol(...
                'parent', obj.hPanel, ...
                'Tag', 'SimulatedModeCheckBox', ...
                'Style', 'checkbox', ...
                'String', 'Run in Simulated Mode', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [46 ph-475 200 22]);
            
            obj.reload();
        end
        
        function delete(obj)
        end
        
        function applySmartDefaultSettings(obj)
            % pick a default daq for the shutter. If there is a PXI chassis
            % choose a daq in the chassis
            
            s.simulated = isempty(obj.hConfigEditor.availableDaqs) || all([obj.hConfigEditor.daqInfo.simulated]);
            
            if s.simulated || isempty(obj.hConfigEditor.availableRios)
                obj.applyVarStruct(s);
                obj.reload();
            end
        end
        
        function reload(obj)
            % reload settings from the file
            mdfData = obj.getCurrentMdfDataStruct();
            
            if ~isempty(mdfData)
                if isfield(mdfData, 'objectiveResolution')
                    obj.hObjectiveResolutionEdit.String = mdfData.objectiveResolution;
                else
                    obj.hObjectiveResolutionEdit.String = '15';
                end
                
                if isfield(mdfData, 'startUpScript')
                    obj.startupScript = mdfData.startUpScript;
                else
                    obj.startupScript = '';
                end
                
                if numel(mdfData.components)
                    for i=1:numel(mdfData.components)
                        if isa(mdfData.components{i}, 'function_handle')
                            mdfData.components{i} = func2str(mdfData.components{i});
                        end
                        [tf, idx] = ismember(mdfData.components{i}, obj.knownComponentMapping);
                        if tf
                            mdfData.components{i} = obj.knownComponents{idx};
                        else
                            obj.customComponents{end+1} = mdfData.components{i};
                        end
                    end
                    obj.customComponents = unique(obj.customComponents);
                    obj.hAddlComponentsTable.ColumnFormat = {[obj.knownComponents obj.customComponents {'Custom...'}] 'char'};
                    
                    dat = cellfun(@(c1){c1 obj.delChar},mdfData.components,'UniformOutput',false);
                    dat = vertcat(dat{:});
                    dat(end+1,:) = {'' obj.delChar};
                    obj.hAddlComponentsTable.Data = dat;
                end
                
                obj.hSimulatedModeCheckBox.Value = mdfData.simulated;
            end
        end
        
        function s = getNewVarStruct(obj)
            comps = obj.hAddlComponentsTable.Data(1:end-1,1);
            [tf, idx] = ismember(comps, obj.knownComponents);
            idx(idx==0) = [];
            comps(tf) = obj.knownComponentMapping(idx);
            
            isFunc = cellfun(@(s)s(1)=='@',comps);
            comps(isFunc) = cellfun(@str2func,comps(isFunc),'UniformOutput',false);
            
            s = struct('simulated', logical(obj.hSimulatedModeCheckBox.Value),'components',{comps'},...
                'objectiveResolution',str2double(obj.hObjectiveResolutionEdit.String), 'startUpScript', obj.startupScript);
        end
    end
    
    %% prop acces
    methods
        function set.startupScript(obj,v)
            if ~isempty(v) && ~isvarname(v)
                fprintf(2, 'Must be a valid MATLAB script name format.\n');
                v = matlab.lang.makeValidName(v);
            end
            obj.startupScript = v;
        end
        
        function v = get.simulated(obj)
            v = obj.hSimulatedModeCheckBox.Value;
        end
        
        function v = get.hasThorECU(obj)
            v = ismember('Thorlabs ECU 1',obj.hAddlComponentsTable.Data(1:end-1,1));
        end
        
        function v = get.hasBScope2(obj)
            v = ismember('Thorlabs B-Scope 2',obj.hAddlComponentsTable.Data(1:end-1,1));
        end
        
        function v = get.hasPMTController(obj)
            v = ismember('Analog PMT Controller',obj.hAddlComponentsTable.Data(1:end-1,1));
        end
    end
    
    methods
        function KeyFcn(obj,~,evt)
            switch evt.EventName
                case 'KeyRelease'
                    obj.keyDown = false;
                case 'KeyPress'
                    obj.keyDown = true;
            end
        end
        
        function compCellSelFcn(obj,~,evt)
            if size(evt.Indices,1) == 1 && evt.Indices(2) == 2
                if obj.keyDown
                    d = obj.hAddlComponentsTable.Data;
                    obj.hAddlComponentsTable.Data = {};
                    obj.hAddlComponentsTable.Data = d;
                    obj.keyDown = false;
                else
                    obj.hAddlComponentsTable.Data(evt.Indices(1),:) = [];
                end
                obj.compCellEditFcn();
            end
        end
        function compCellEditFcn(obj,varargin)
            dat = obj.hAddlComponentsTable.Data;
            
            % handle custom selection
            i = find(strcmp(dat(:,1),'Custom...'));
            if ~isempty(i)
                resp = inputdlg(['Enter a custom component. This can either be a class name (ex ''dabs.thorlabs.ECU1'') or an anonymous function. If it is a class, the constructor must'...
                    ' take the hSI model handle as a parameter. If it is an anonymous function, it must take the hSI model handle as a parameter and return an object handle.'],...
                    'Select Custom Component',1,{'@(hSI)myCustomComponentFunc(hSI)'});
                if isempty(resp)
                    dat(i,:) = [];
                else
                    dat(i,1) = resp;
                    obj.customComponents = unique([obj.customComponents resp]);
                    obj.hAddlComponentsTable.ColumnFormat = {[obj.knownComponents obj.customComponents {'Custom...'}] 'char'};
                end
            end
            
            % make sure there is a blank row
            if size(dat,1) < 1
                lr = [];
            else
                lr = dat(end,:);
            end
            
            if isempty(lr) || ~isempty(lr{1})
                dat(end+1,:) = {'' obj.delChar};
            end
            
            obj.hAddlComponentsTable.Data = dat;
        end
        
        function editScr(obj,varargin)
            if isempty(obj.startupScript)
                resp = inputdlg('Enter the name of a matlab script on the current search path. If it does not exist it will be created in the current directory.','Select Script',1,{'myCustomScript'});
                if ~isempty(resp)
                    obj.startupScript = resp{1};
                    edit(obj.startupScript);
                end
            else
                edit(obj.startupScript);
            end
        end
    end
end


%--------------------------------------------------------------------------%
% SIPage.m                                                                 %
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
