classdef AsyncSerialQueue < handle    
    properties (SetAccess = private)
        isCallbackPending = false;
        isSyncCallInProgress = false;
        pendingCallback = [];
        pendingRspSize = 0;
        queue = {};
    end
    
    properties
        maxQueueLength = 10;
        ErrorFcn = function_handle.empty(1,0);
    end
    
    properties (SetAccess = private, Hidden)
        hAsyncSerial;
    end
    
    methods
        function obj = AsyncSerialQueue(varargin)
            try
                obj.hAsyncSerial = dabs.generic.AsyncSerial(varargin{:});
                obj.hAsyncSerial.BytesAvailableFcn = @obj.bytesAvailableCb;
                obj.hAsyncSerial.ErrorFcn = @obj.errorCb;
            catch ME
                obj.delete();
                rethrow(ME);
            end
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hAsyncSerial);
        end
    end
    
    %% Public methods
    methods
        function rsp = writeRead(obj,data,numRspBytes, timeout)
%             if nargin < 3 || isempty(numRspBytes)
%                 numRspBytes = 0;
%             end
            if nargin < 4 || isempty(timeout)
                timeout = 5;
            end
            
            assert(isa(data,'uint8'),'Data must be of type uint8.');
            assert(isvector(data),'Data must be a vector');
            
            if isempty(numRspBytes)
                
            elseif isnumeric(numRspBytes) && ~isempty(numRspBytes)
                assert(isnumeric(numRspBytes)&&isscalar(numRspBytes)&&numRspBytes>=0);
            else
                assert(ischar(numRspBytes)&&isscalar(numRspBytes));
            end
            
            obj.isSyncCallInProgress = true;
            try
                % process outstanding callback (if any) synchronously
                obj.processCallback();
                obj.flushInputBuffer();
                
                obj.hAsyncSerial.fwrite(data);
                
                rsp = uint8.empty(0,1);
                
                if ischar(numRspBytes)
                    terminationCharacter = uint8(numRspBytes);
                    s = tic();
                    while isempty(rsp) || ~isequal(rsp(end),terminationCharacter)
                        rsp(end+1) = obj.hAsyncSerial.fread(1,timeout);
                        assert(toc(s)<timeout,'AsyncSerialQueue: Timed out while wainting for response');
                    end
                else
                    rsp = obj.hAsyncSerial.fread(numRspBytes,timeout);
                end
                
                cleanup();
            catch ME
               cleanup();
               rethrow(ME);
            end
            
            function cleanup()
                obj.isSyncCallInProgress = false;
                obj.checkQueue();
            end
        end
        
        function writeReadAsync(obj,data,numRspBytes,callback)
            assert(isa(data,'uint8'),'Data must be of type uint8.');
            assert(isvector(data),'Data must be a vector');
            if isnumeric(numRspBytes)
                assert(isnumeric(numRspBytes)&&isscalar(numRspBytes)&&numRspBytes>=0);
            else
                assert(ischar(numRspBytes)&&isscalar(numRspBytes));
            end
%             assert(isnumeric(numRspBytes)&&isscalar(numRspBytes)&&numRspBytes>0);
            assert(isa(callback,'function_handle'));
            
            obj.enqueue(data,numRspBytes,callback);
            obj.checkQueue();
        end
    end
    
    %% Internal methods
    methods (Access = protected)        
        function bytesAvailableCb(obj,src,evt)
            obj.processCallback();
        end
        
        function errorCb(obj,src,evt)
            if ~isempty(obj.ErrorFcn)
                obj.ErrorFcn(obj,evt);
            end            
        end
        
        function processCallback(obj)
            if ~obj.isCallbackPending
               return
            end
            
            callback = obj.pendingCallback;
            bytesToRead = obj.pendingRspSize;
            
            obj.pendingCallback = [];
            obj.pendingRspSize = 0;
            obj.isCallbackPending = false;
            
            rsp = uint8.empty(0,1);
            
            try
                timeout_s = 5;
                
                if ischar(bytesToRead)
                    terminationCharacter = uint8(bytesToRead);
                    s = tic();
                    while isempty(rsp) || ~isequal(rsp(end),terminationCharacter)
                        rsp(end+1) = obj.hAsyncSerial.fread(1,timeout_s);
                        assert(toc(s)<timeout_s,'AsyncSerialQueue: Timed out while wainting for response');
                    end
                else
                    rsp = obj.hAsyncSerial.fread(bytesToRead,timeout_s);
                end
                
                callback(rsp);
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
            
            try
                obj.checkQueue();
            catch ME
                most.ErrorHandler.logAndReportError(ME);
            end
        end
        
        function flushInputBuffer(obj, tfSilent)
            if nargin < 2 || isempty(tfSilent)
               tfSilent = false; 
            end
            [nBytes,data] = obj.hAsyncSerial.flushInputBuffer();
            if ~tfSilent && nBytes > 0
                
                most.idioms.warn('Serial communication dropped %d bytes: %s',nBytes,mat2str(data'));
            end
        end
        
        function enqueue(obj,data,numRspBytes,callback)
            assert(numel(obj.queue) < obj.maxQueueLength,'Reached maximum queue length of %d.',obj.maxQueueLength);
            obj.queue{end+1} = {data,numRspBytes,callback};
        end
        
        function [data,numRspBytes,callback] = dequeue(obj)
            packet = obj.queue{1};
            obj.queue(1) = [];
            
            data = packet{1};
            numRspBytes = packet{2};
            callback = packet{3};
        end
        
        function checkQueue(obj)
            if ~obj.isCallbackPending && ~obj.isSyncCallInProgress && ~isempty(obj.queue)
                obj.isCallbackPending = true;
                [data,numRspBytes,callback] = obj.dequeue();
                obj.flushInputBuffer();
                obj.pendingRspSize = numRspBytes;
                obj.pendingCallback = callback;
                obj.hAsyncSerial.fwrite(data);
            end
        end
    end
    
    methods
        function set.maxQueueLength(obj,val)
            validateattributes(val,{'numeric'},{'scalar','integer','positive'});
            obj.maxQueueLength = val;
        end
        
        function set.ErrorFcn(obj,val)
            if isempty(val)
                val = function_handle.empty(1,0);
            else
                validateattributes(val,{'function_handle'},{'scalar'});
            end
            
            obj.ErrorFcn = val;
        end
    end
end

%--------------------------------------------------------------------------%
% AsyncSerialQueue.m                                                       %
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
