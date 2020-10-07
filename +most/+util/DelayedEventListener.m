classdef DelayedEventListener < handle    
    properties
        delay;
        enabled = true;
    end
    
    properties (Access = private)
       hDelayTimer;
       delayTimerRunning = false;
       lastDelayFunctionCall;
       functionHandle;
       hListener;
       evtList = {};
    end
    
    methods
        function obj = DelayedEventListener(delay,varargin)            
            obj.hDelayTimer = timer(...
                'TimerFcn',@obj.doNothing,...
                'StopFcn',@obj.timerCallback,...
                'BusyMode','drop',...
                'ExecutionMode','singleShot',...
                'StartDelay',1,... % overwritten later
                'ObjectVisibility','off');
            
            obj.delay = delay;
            obj.hListener = addlistener(varargin{:});
            
            obj.functionHandle = obj.hListener.Callback;
            obj.hListener.Callback = @(varargin)obj.delayFunction(varargin{:});
            
            listenerSourceNames = strjoin(cellfun(@(src)class(src),obj.hListener.Source,'UniformOutput',false));
            set(obj.hDelayTimer,'Name',sprintf('Delayed Event Listener Timer %s:%s',listenerSourceNames,obj.hListener.EventName));
        end
        
        function delete(obj)
            obj.hDelayTimer.StopFcn = []; % stop will be called when deleting the timer. Avoid the stop function
            most.idioms.safeDeleteObj(obj.hListener);
            most.idioms.safeDeleteObj(obj.hDelayTimer);
        end
    end
    
    methods
        function delayFunction(obj,src,evt)
            if obj.enabled
                % restart timer
                obj.lastDelayFunctionCall = tic();
                obj.evtList{end+1} = evt;
                if ~obj.delayTimerRunning
                    obj.hDelayTimer.StartDelay = obj.delay;
                    obj.delayTimerRunning = true;
                    start(obj.hDelayTimer);
                end 
            end
        end
        
        function doNothing(obj,varargin)
        end
        
        function timerCallback(obj,varargin)
            try
                dt = toc(obj.lastDelayFunctionCall);
                newDelay = obj.delay-dt;
                
                if newDelay > 0
                    % rearm timer
                    newDelay = (ceil(newDelay*1000)) / 1000; % timer delay is limited to 1ms precision
                    obj.hDelayTimer.StartDelay = newDelay;
                    start(obj.hDelayTimer);
                else
                    % execute delayed callback
                    obj.delayTimerRunning = false;
                    if ~isempty(obj.evtList)
                        eL = obj.evtList;
                        obj.evtList = {};
                        obj.executeFunctionHandle(obj.hListener.Source,eL);
                    end
                end
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
        end
        
        function executeFunctionHandle(obj,varargin)
            try
                obj.functionHandle(varargin{:});
            catch ME
                msg = sprintf('Error occured while handling an event. The last command may not have produced the expected behavior.\nError message: %s', ME.message);
                most.ErrorHandler.logAndReportError(ME, msg, 1);
            end
        end
        
        function flushEvents(obj)
            stop(obj.hDelayTimer);
            obj.delayTimerRunning = false;
            if ~isempty(obj.evtList)
                try
                    eL = obj.evtList;
                    obj.evtList = {};
                    obj.executeFunctionHandle(obj.hListener.Source,eL);
                catch ME
                    most.ErrorHandler.logAndReportError(ME);
                end
            end
        end
    end
    
    methods
        function set.delay(obj,val)
            validateattributes(val,{'numeric'},{'scalar','positive','nonnan','finite'});
            val = (ceil(val*1000)) / 1000; % timer delay is limited to 1ms precision
            obj.delay = val;
        end
    end
end


%--------------------------------------------------------------------------%
% DelayedEventListener.m                                                   %
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
