function OK = blockingMsgbox(varargin)
    % blocks until user clicks OK or closes window
    % returns true if user clicked OK, returns false if user closes window
    
    OK = false;
    hFig = msgbox(varargin{:});
    
    hFig.KeyPressFcn = @doKeyPress;
    
    mask = arrayfun(@(c)isa(c,'matlab.ui.control.UIControl'),hFig.Children);    
    hButton = hFig.Children(mask);
    hButton.Callback = @clickedOK;
    
    if most.idioms.isValidObj(hFig)
        waitfor(hFig);
    end
    
    function clickedOK(src,evt)
        OK = true;
        delete(hFig);
    end

    function doKeyPress(src,evt)
        switch(evt.Key)
            case {'return','space'}
                OK = true;
                delete(hFig);
            case 'escape'
                delete(hFig);
        end
    end
end

%--------------------------------------------------------------------------%
% blockingMsgbox.m                                                         %
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
