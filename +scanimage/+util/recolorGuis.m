function changedList = recolorGuis(newColor)
    % Utility to change SI gui background color. Three modes:
    %
    % call with a color (1x3 vector) to change SI gui backgrounds to a new
    % color. returns a list of gui objects that were modified and the
    % original color value
    %
    % call with only a return value to retrieve list of gui objects that were modified and the
    % original color value
    % 
    % call with no input or output arguments to restore guis to
    % original color.
    
    persistent changed;
    
    changedList = changed;
    
    if ~isempty(changed) && (~nargout || nargin)
        for ii = 1:numel(changed)
            item = changed{ii};
            if most.idioms.isValidObj(item{1})
                item{1}.(item{2}) = item{3};
            end
        end
        changed = {};
    end
    
    if nargin
        try
            recolorGuisInt(evalin('base','hSICtl.hGUIsArray'));
        catch
            error('Could not find ScanImage GUI');
        end
        try
            changedList = changed;
        catch ME
            error('Failed to change SI GUI color. Error message: %s',ME.message);
        end
    end
    
    function recolorGuisInt(guis)
        n = numel(guis);
        for i = 1:n
            gui = guis(i);
            
            if isa(gui,'matlab.ui.Figure')
                tryProp(gui,'Color',true);
            elseif isa(gui,'matlab.ui.container.Panel') || isa(gui,'matlab.ui.container.internal.UIFlowContainer')
                tryProp(gui,'BackgroundColor',true);
            elseif ~isbutton(gui)
                tryProp(gui,'BackgroundColor',false);
%                 tryProp(gui,'Color',false);
%                 tryProp(gui,'ForegroundColor',false);
            end
            
            if isprop(gui,'Children')
                recolorGuisInt(gui.Children);
            end
        end
    end
    
    function tryProp(obj,prop,changeEmpty)
        defCol = .94*ones(1,3);
        if isprop(obj,prop)
            c = obj.(prop);
            if (changeEmpty && isempty(c)) || (isnumeric(c) && (numel(c) == 3) && (sum(abs(c-defCol)) < .1))
                obj.(prop) = newColor;
                changed{end+1} = {obj prop c};
            end
        end
    end
    
    function v = isbutton(obj)
        v = isa(obj,'matlab.ui.control.UIControl') && (strcmp(obj.Style,'pushbutton') || strcmp(obj.Style,'togglebutton'));
    end
end


%--------------------------------------------------------------------------%
% recolorGuis.m                                                            %
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
