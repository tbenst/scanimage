classdef MotorsPage < scanimage.guis.configuration.ConfigurationPage
    
    properties
        hMotorPanel;
        hNoSelText;
        hMotorList;
        hScalingTable;
        hDimensionTable;
        hRemove;
        
        hComText;
        hComPopup;
        
        motors;
        hideHeadings = {};
    end
    
    properties (SetObservable)
        scaleXYZ = [1 1 1];
        axisMovesObjective = [false false false];
        
        mtrChoices = {};
        motorName = '';
        controllerType = '';
        
        comChoices = {};
        comPort = '';
        
        additionalParams;
        shortVelocity;
        longVelocity;
        moveCompleteDelay;
        
        motorList = {};
        comPortSelections = {};
        
        currentMotorRegistryEntry;
    end
    
    properties (Constant)
        modelClass = 'scanimage.components.Motors';
    end
    
    methods
        function obj = MotorsPage(hConfigEditor, create)
            if nargin < 2 || isempty(create)
                create = false;
            end
            obj = obj@scanimage.guis.configuration.ConfigurationPage(hConfigEditor,create);
            
            obj.listLabel = 'Stage Controllers (Motors)';
            obj.heading = 'Motors';
            obj.descriptionText = 'Configure stage controllers to enable view and control of the stage position in ScanImage. Multiple motors can be configured with physical axes mapped to the ScanImage XYZ coordinate system.';
            
            ph = 770;
            obj.hPanel = uipanel('parent',[],'BorderType','none','units','pixels','position',[0 0 990 ph]);
        
            uicontrol('parent', obj.hPanel, ...
                'Style', 'text', ...
                'HorizontalAlignment', 'left', ...
                'String', 'Configured Motor Controllers', ...
                'fontsize',10,...
                'Units', 'pixels', ...
                'Position', [46 ph-33 200 16]);
            
            obj.hMotorList = most.gui.uicontrol('parent', obj.hPanel, ...
                'Style', 'listbox', ...
                'Units', 'pixels', ...
                'callback',@obj.selectionChanged,...
                'Bindings',{obj 'motorList' 'choices'},...
                'Position', [46 ph-97 190 60]);

            uicontrol('parent', obj.hPanel, ...
                'string','Add New',...
                'Units', 'pixels', ...
                'Position', [46 ph-132 74 28], ...
                'callback',@obj.addNew);
            
            obj.hRemove = uicontrol('parent', obj.hPanel, ...
                'string','Remove Selected',...
                'Units', 'pixels', ...
                'Position', [126 ph-132 110 28], ...
                'callback',@obj.removeSelected);
                        
            x = '<html><table border=0 width=50><TR><TD><center>X</center></TD></TR></table></html>';
            y = '<html><table border=0 width=50><TR><TD><center>Y</center></TD></TR></table></html>';
            z = '<html><table border=0 width=50><TR><TD><center>Z</center></TD></TR></table></html>';
            obj.hScalingTable = uitable('parent', obj.hPanel, ...
                'ColumnName', {'Axis' 'Scaling' 'Effect'}, ...
                'Data',{x 1 'moves sample'; y 1 'moves sample'; z 1 'moves sample'},...
                'ColumnFormat', {'char' 'numeric' {'moves sample' 'moves objective'}}, ...
                'ColumnEditable', [false, true, true], ...
                'ColumnWidth', {50, 55, 115}, ...
                'RowName', [],...
                'CellEditCallback',@obj.tblScalingCb,...
                'Units', 'pixels', ...
                'Position', [246 ph-97 237 80]);
            
            mph = 300;
            mpw = 780;
            obj.hMotorPanel = uipanel( ...
                'parent', obj.hPanel, ...
                'Units', 'pixels', ...
                'fontsize',10,...
                'Position', [46 ph-164-mph mpw mph]);
            
            uicontrol( ...
                'parent', obj.hMotorPanel, ...
                'Style', 'text', ...
                'String', 'Configure Motor:', ...  
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'fontsize',10,...
                'Position', [46 mph-50 676 16]);
            
            obj.hNoSelText = uicontrol( ...
                'parent', obj.hMotorPanel, ...
                'Style', 'text', ...
                'String', 'Add or select a motor controller above in order to configure it...', ...  
                'HorizontalAlignment', 'center', ...
                'FontSize',11,...
                'ForegroundColor',.5*ones(1,3),...
                'Units', 'pixels', ...
                'Visible','off',...
                'Position', [1 mph-56 mpw-2 30]);
            
            uicontrol( ...
                'parent', obj.hMotorPanel, ...
                'Style', 'text', ...
                'String', 'Motor Name', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [46 mph-74 108 14]);
            
            most.gui.uicontrol( ...
                'parent', obj.hMotorPanel, ...
                'Style', 'edit', ...
                'String', '', ...
                'TooltipString', 'Enter a unique name for the motor.',...
                'Units', 'pixels', ...
                'Bindings', {{obj,'motorName','string'}},...
                'Position', [206 mph-78 150 22]);
            
            uicontrol(...
                'parent', obj.hMotorPanel, ...
                'Style', 'text', ...
                'String', 'Controller Type', ...
                'TooltipString', '', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [46 mph-100 108 14]);
        
            most.gui.uicontrol(...
                'parent', obj.hMotorPanel, ...
                'Style', 'popupmenu', ...
                'String', {'None'}, ...
                'TooltipString', '', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Bindings',{{obj 'mtrChoices' 'choices'} {obj 'controllerType' 'choice'}},...
                'Position', [206 mph-104 150 22]);   
            
            obj.hComText = uicontrol(...
                'parent', obj.hMotorPanel, ...
                'Style', 'text', ...
                'String', 'Serial COM Port', ...
                'TooltipString', '', ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [46 mph-126 108 14]);
        
            obj.hComPopup = most.gui.popupMenuEdit(...
                'parent', obj.hMotorPanel, ...
                'Units', 'pixels', ...
                'Bindings',{{obj 'comChoices' 'choices'} {obj 'comPort' 'string'}},...
                'Position', [206 mph-130 60 22]);            
            
            uicontrol( ...
                'parent', obj.hMotorPanel, ...
                'Style', 'text', ...
                'String', 'Configure the mapping between the motor axes and ScanImage''s XYZ coordinate system.', ...  
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'fontsize',10,...
                'Position', [46 mph-190 676 32]);
            
            x = '<html><table border=0 width=75><TR><TD><center>1</center></TD></TR></table></html>';
            y = '<html><table border=0 width=75><TR><TD><center>2</center></TD></TR></table></html>';
            z = '<html><table border=0 width=75><TR><TD><center>3</center></TD></TR></table></html>';
            obj.hDimensionTable = uitable('parent', obj.hMotorPanel, ...
                'ColumnName', {'Physical|Axis' 'ScanImage|Coordinates'}, ...
                'Data',{x 'X'; y 'Y'; z 'Z';},...
                'ColumnFormat', {'numeric', {' ' 'X' 'Y' 'Z'},}, ...
                'ColumnEditable', [false, true], ...
                'ColumnWidth', {75, 75}, ...
                'RowName', [],...
                'CellEditCallback',@obj.tblCb,...
                'Units', 'pixels', ...
                'Position', [46 mph-280 180 96]);
            
            obj.reload();
        end
        
        function delete(obj)
        end
        
        function reload(obj)
            entries = obj.hConfigEditor.hMotorRegistryNew.getEntries();
            obj.mtrChoices = {entries.displayName};
            obj.comChoices = [{'None'}; obj.hConfigEditor.availableComPorts];
            
            mdfData = obj.getCurrentMdfDataStruct();
            emps = arrayfun(@(s)isempty(s.name),mdfData.motors);
            obj.scaleXYZ = mdfData.scaleXYZ;
            obj.axisMovesObjective = mdfData.axisMovesObjective;
            obj.motors = mdfData.motors(~emps);
            
            obj.comPortSelections = {};
            obj.hideHeadings = {};
            motorRegistryEntries = cellfun(@(c)scanimage.components.motors.MotorRegistry.searchEntry(c),{obj.motors.controllerType},'UniformOutput',false);
            for i = numel(obj.motors):-1:1
                comPrt = '';
                
                reg = motorRegistryEntries{i};
                if ~isempty(reg)
                    mdfHeading = sprintf('%s (%s)', reg.mdfHeading, obj.motors(i).name);
                    reg = obj.hConfigEditor.getCurrentMdfDataStruct(mdfHeading);
                end
                if ~isempty(reg) && isfield(reg, 'comPort')
                    comPrt = sprintf('COM%d',reg.comPort);
                    
                    if numel(fieldnames(reg)) == 1
                        obj.hideHeadings{end+1} = mdfHeading;
                    end
                end
                
                obj.comPortSelections{i} = comPrt;
            end
            
            obj.updateMotorListNames();
            obj.hMotorList.Value = 1;
            obj.selectionChanged();
        end
        
        function s = getNewVarStruct(obj)
            s = obj.getCurrentMdfDataStruct();
            
            s.scaleXYZ = obj.scaleXYZ;
            s.axisMovesObjective = obj.axisMovesObjective;
            
            % if there used to be more motors than there are now, make sure
            % the name is blanked on the extra entries
            s.motors = arrayfun(@(s)setfield(s, 'name', ''),s.motors);
            s.motors(1:numel(obj.motors)) = obj.motors;
        end
        
        function postApplyAction(obj)
            % apply com port settings to appropriate pages
            obj.hideHeadings = {};
            
            motorRegistryEntries = cellfun(@(c)scanimage.components.motors.MotorRegistry.searchEntry(c),{obj.motors.controllerType},'UniformOutput',false);
            for i = 1:numel(obj.motors)
                reg = motorRegistryEntries{i};
                if ~isempty(reg) && ismember('most.HasMachineDataFile',superclasses(reg.className))
                    mdfParams = eval(['{' reg.className '.mdfDefault.name}']);
                    
                    if ismember('comPort', mdfParams)
                        mdfHeading = sprintf('%s (%s)', reg.mdfHeading, obj.motors(i).name);
                        
                        comVal = obj.comPortSelections{i};
                        if strncmpi(comVal,'com',3) && (length(comVal) > 3) && all(isstrprop(comVal(4:end), 'digit'))
                            comVal = str2double(comVal(4:end));
                        else
                            comVal = [];
                        end
                        
                        obj.hConfigEditor.hMDF.writeVarToHeading(mdfHeading,'comPort',comVal);
                        
                        if numel(mdfParams) == 1
                            obj.hideHeadings{end+1} = mdfHeading;
                        end
                    end
                end
            end
        end
    end
    
    methods
        function addNew(obj,varargin)
            names = {obj.motors.name};
            n = 0;
            while true
                n = n+1;
                name = sprintf('Motor %d',n);
                if ~ismember(name,names)
                    break
                end
            end
            
            obj.motors(end+1).name = name;
            obj.motors(end).controllerType = 'Simulated';
            obj.motors(end).dimensions = '---';
            
            obj.comPortSelections(end+1) = {''};
            
            obj.updateMotorListNames();
            obj.hMotorList.Value = numel(obj.motors);
            obj.selectionChanged();
        end
        
        function removeSelected(obj,varargin)
            v = obj.hMotorList.Value;
            if (v > 0) && (v <= numel(obj.motors))
                obj.motors(v) = [];
                obj.comPortSelections(v) = [];
            end
            
            obj.updateMotorListNames();
            obj.hMotorList.Value = min(obj.hMotorList.Value,numel(obj.motorList));
            obj.selectionChanged();
        end
        
        function selectionChanged(obj,varargin)
            if isempty(obj.motorList)
                obj.hMotorPanel.Title = '';
                obj.hMotorList.Value = 1;
                set(obj.hMotorPanel.Children, 'visible', 'off');
                obj.hNoSelText.Visible = 'on';
                obj.hRemove.Enable = 'off';
            else
                v = obj.hMotorList.Value;
                
                obj.currentMotorRegistryEntry = obj.hConfigEditor.hMotorRegistryNew.searchEntry(obj.motors(v).controllerType);
                obj.motorName = obj.motors(v).name;
                obj.controllerType = obj.currentMotorRegistryEntry.displayName;

                N = min(3,numel(obj.motors(v).dimensions));
                newDat(1:N,1) = arrayfun(@(x){strrep(x,'-','')},obj.motors(v).dimensions(1:N))';
                
                obj.hDimensionTable.Data(:,2:end) = newDat;
                
                obj.hMotorPanel.Title = ['Motor Settings: ' obj.motorList{v}];
                set(obj.hMotorPanel.Children, 'visible', 'on');
                obj.hNoSelText.Visible = 'off';
                obj.hRemove.Enable = 'on';
                
                obj.updateComVisibility();
                obj.comPort =  obj.comPortSelections{v};
            end
        end
        
        function hasCom = updateComVisibility(obj)
            hasMdf = ~isempty(obj.currentMotorRegistryEntry) && ismember('most.HasMachineDataFile',superclasses(obj.currentMotorRegistryEntry.className));
            hasCom = hasMdf && ismember('comPort', eval(['{' obj.currentMotorRegistryEntry.className '.mdfDefault.name}']));
            set([obj.hComText obj.hComPopup.hPanel], 'visible', obj.hConfigEditor.tfMap(hasCom));
        end
        
        function updateMotorListNames(obj)
            if isempty(obj.motors)
                obj.motorList = {};
            else
                names = {obj.motors.controllerType};
                dat = cellfun(@(x)obj.hConfigEditor.hMotorRegistryNew.searchEntry(x),names,'UniformOutput',false);
                dat = horzcat(dat{:});
                obj.motorList = arrayfun(@mtrStr,dat,obj.motors);
            end
            
            function str = mtrStr(rd,d)
                dims = strrep(d.dimensions,'-','');
                if isempty(dims)
                    str = {[d.name ' (' rd.displayName ')']};
                else
                    str = {[d.name ' (' rd.displayName ' - ' dims ')']};
                end
            end
        end
        
        function tblCb(obj,src,~)
            idx = obj.hMotorList.Value;
            
            dims = strtrim(src.Data(:,2)');
            dims(cellfun(@isempty,dims)) = {'-'};
            obj.motors(idx).dimensions = [dims{:}];
            
            obj.updateMotorListNames();
        end
        
        function tblScalingCb(obj,src,~)
            scale = obj.hScalingTable.Data(:,2);
            effect = obj.hScalingTable.Data(:,3);
            
            obj.axisMovesObjective = cellfun(@(v)strcmpi(v,'moves objective'),effect(:)');            
            obj.scaleXYZ = horzcat(scale{:});

        end
        
        function updateScalingTable(obj)
            data = obj.hScalingTable.Data;
            data{1,2} = obj.scaleXYZ(1);
            data{2,2} = obj.scaleXYZ(2);
            data{3,2} = obj.scaleXYZ(3);
            
            data{1,3} = most.idioms.ifthenelse(obj.axisMovesObjective(1),'moves objective','moves sample');
            data{2,3} = most.idioms.ifthenelse(obj.axisMovesObjective(2),'moves objective','moves sample');
            data{3,3} = most.idioms.ifthenelse(obj.axisMovesObjective(3),'moves objective','moves sample');
            
            obj.hScalingTable.Data = data;
        end
    end
    
    %% Prop access
    methods
        function set.motorName(obj,v)
            obj.motorName = v;
            idx = obj.hMotorList.Value;
            obj.motors(idx).name = obj.motorName;
            obj.updateMotorListNames();
        end
        
        function set.controllerType(obj,v)
            obj.controllerType = v;
            
            idx = obj.hMotorList.Value;
            obj.currentMotorRegistryEntry = scanimage.components.motors.MotorRegistry.searchEntry(v);
            obj.motors(idx).controllerType = obj.currentMotorRegistryEntry.displayName;
            obj.updateMotorListNames();
            obj.updateComVisibility();
        end
        
        function set.comPort(obj,v)
            if isempty(v)
                v = 'None';
            elseif all(isstrprop(v, 'digit'))
                v = ['COM' v];
            end
            
            obj.comPort = v;
            
            idx = obj.hMotorList.Value;
            obj.comPortSelections{idx} = v;
        end
        
        function set.scaleXYZ(obj,v)
            % coerce v
            if ~isnumeric(v) || ~isvector(v)
                v = [1 1 1];
            end
            
            if numel(v) ~= 3
                % trim
                v(end+1:3) = 1;
                v(4:end) = [];
            end
            
            v = real(v);
            v(isnan(v)) = 1;
            v(isinf(v)) = 1;
            v(v==0) = 1;
            
            obj.scaleXYZ = v(:)';
            obj.updateScalingTable();
        end
        
        function set.axisMovesObjective(obj,v)
            if ~islogical(v) || ~isvector(v)
                v = [false false false];
            end
            
            if numel(v) ~= 3
                v(end+1:3) = 1;
                v(4:end) = [];
            end
            
            obj.axisMovesObjective = v(:)';
            obj.updateScalingTable();
        end
    end
end


%--------------------------------------------------------------------------%
% MotorsPage.m                                                             %
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
