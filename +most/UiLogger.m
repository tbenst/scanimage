classdef UiLogger < handle
    
    properties
        originalCallbacks = cell(1,2000);
        originalCallbacksCtr = 1;
        
        log = {};
        logPtr = 1;
        logLength = 5000;
    end
    
    methods
        function obj = UiLogger(hSICtl)
            obj.log = repmat({''},obj.logLength,1);
            
            obj.captureAllGuis(hSICtl.hGUIsArray);
            obj.originalCallbacks(obj.originalCallbacksCtr:end) = [];
            
            most.ErrorHandler.setErrorCallback(@obj.genericErrorCallback);
        end
        
        function delete(obj)
            for i = 1:numel(obj.originalCallbacks)
                o = obj.originalCallbacks{i};
                if most.idioms.isValidObj(o{1})
                    if isprop(o, 'Callback')
                        o{1}.Callback = o{2};
                    else
                        o{1}.MenuSelectedFcn = o{2};
                    end
                end
            end
        end
        
        function captureAllGuis(obj,objs,guiName)
            for i = 1:numel(objs)
                if isa(objs(i),'matlab.ui.control.UIControl')
                    hCtl = objs(i);
                    cb = hCtl.Callback;
                    
                    replaceFunc = ~isa(cb,'function_handle') || ~strncmp(func2str(cb),'@(varargin)guiCallback',22);
                    if replaceFunc
                        ctlName = hCtl.Tag;
                        if isempty(ctlName)
                            style = hCtl.Style;
                            if ((length(style) > 5) && strcmp('button',style(end-5:end)))...
                                    || ((length(style) > 7) && strcmp('checkbox',style(end-7:end)))
                                ctlName = [matlab.lang.makeValidName(hCtl.String) '_' style];
                            else
                                ctlName = ['Unknown_' style];
                            end
                        end
                        nm = [guiName '.' ctlName];
                        
                        hCtl.Callback = @(varargin)obj.guiCallback(cb,nm,varargin);
                        
                        obj.originalCallbacks{obj.originalCallbacksCtr} = {hCtl cb};
                        obj.originalCallbacksCtr = obj.originalCallbacksCtr + 1;
                    end
                elseif isa(objs(i),'matlab.ui.container.Menu') && isprop(objs(i),'MenuSelectedFcn') && ~isempty(objs(i).MenuSelectedFcn) && isa(objs(i).Parent,'matlab.ui.container.Menu')
                    hCtl = objs(i);
                    cb = hCtl.MenuSelectedFcn;
                    
                    replaceFunc = ~isa(cb,'function_handle') || ~strncmp(func2str(cb),'@(varargin)guiCallback',22);
                    if replaceFunc
                        parname = matlab.lang.makeValidName(hCtl.Parent.Text);
                        ctlName = hCtl.Tag;
                        if isempty(ctlName)
                            ctlName = matlab.lang.makeValidName(hCtl.Text);
                        end
                        nm = [guiName '.' parname '_menu.' ctlName];
                        
                        hCtl.MenuSelectedFcn = @(varargin)obj.guiCallback(cb,nm,varargin);
                        
                        obj.originalCallbacks{obj.originalCallbacksCtr} = {hCtl cb};
                        obj.originalCallbacksCtr = obj.originalCallbacksCtr + 1;
                    end
                elseif isprop(objs(i),'Children') && ~isempty(objs(i).Children)
                    if isa(objs(i),'matlab.ui.Figure')
                        guiName = matlab.lang.makeValidName(objs(i).Name);
                    end
                    if isempty(guiName)
                        guiName = objs(i).Tag;
                    end
                    if isempty(guiName)
                        guiName = 'Unknown_GUI';
                    end
                    obj.captureAllGuis(objs(i).Children,guiName);
                end
            end
        end
        
        function guiCallback(obj,usrCallback,nm,args)
            try
                hCtl = args{1};
                if isa(hCtl, 'matlab.ui.container.Menu')
                    newVal = '';
                elseif strcmp(hCtl.Style, 'edit')
                    newVal = [' -> ' hCtl.String];
                else
                    newVal = [' -> ' num2str(hCtl.Value)];
                end
                obj.addToLog([datestr(clock) ': ' nm newVal]);
            catch
            end
            
            if ~isempty(usrCallback)
                try
                    usrCallback(args{:});
                catch ME
                    msg = sprintf('Error occured in GUI action: %s', ME.message);
                    most.ErrorHandler.logAndReportError(ME, msg);
                    if isa(hCtl, 'matlab.ui.container.Menu')
                        obj.flashMenu(hCtl);
                    else
                        obj.flashCtl(hCtl);
                    end
                end
            end
        end
        
        function addToLog(obj,s)
            obj.log{obj.logPtr} = s;
            if obj.logPtr >= obj.logLength
                obj.logPtr = 1;
            else
                obj.logPtr = obj.logPtr + 1;
            end
        end
        
        function logStr = printLog(obj)
            obj.rotateLog();
            s = strjoin([obj.log(~cellfun('isempty',obj.log)); {''}],'\n');
            if nargout < 1
                fprintf(1,s);
            else
                logStr = s;
            end
        end
        
        function rotateLog(obj)
            if ~isempty(obj.log{obj.logPtr})
                obj.log = [obj.log(obj.logPtr:end); obj.log(1:obj.logPtr-1)];
            end
            
            e = cellfun('isempty',obj.log);
            obj.logPtr = find(e,1);
            if isempty(obj.logPtr)
                obj.logPtr = 1;
            end
        end
        
        function flashCtl(~,hCtl)
            try
                N = 2;
                t = 0.1;
                oc = hCtl.BackgroundColor;
                for i = 1:N
                    hCtl.BackgroundColor = [1 .75 .75];
                    drawnow('nocallbacks');
                    most.idioms.pauseTight(t);
                    hCtl.BackgroundColor = oc;
                    if i < N
                        drawnow('nocallbacks');
                        most.idioms.pauseTight(.05);
                    end
                end
            catch
            end
        end
        
        function flashMenu(~,hCtl)
            try
                while isa(hCtl.Parent, 'matlab.ui.container.Menu')
                    hCtl = hCtl.Parent;
                end
                
                N = 2;
                t = 0.1;
                oc = hCtl.ForegroundColor;
                for i = 1:N
                    hCtl.ForegroundColor = 'r';
                    drawnow('nocallbacks');
                    most.idioms.pauseTight(t);
                    hCtl.ForegroundColor = oc;
                    if i < N
                        drawnow('nocallbacks');
                        most.idioms.pauseTight(.05);
                    end
                end
            catch
            end
        end
        
        function genericErrorCallback(obj,ME)
            obj.addToLog(['Error occured (' most.ErrorHandler.getMEUuid(ME) '): ' ME.message]);
        end
    end
    
    methods
        function set.logLength(obj,v)
            if v ~= obj.logLength
                obj.rotateLog();
                obj.logLength = v;
                
                N = numel(obj.log);
                if v > N
                    obj.log(end+1:v) = {''};
                    obj.logPtr = N + 1;
                elseif obj.logPtr == 1
                    obj.log = obj.log(end-v+1:end);
                elseif obj.logPtr >= v
                    obj.log = obj.log(obj.logPtr-v+1:obj.logPtr);
                    obj.logPtr = 1;
                else
                    obj.log(v+1:end) = [];
                end
            end
        end
    end
end


%--------------------------------------------------------------------------%
% UiLogger.m                                                               %
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
