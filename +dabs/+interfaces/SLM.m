classdef SLM < handle
    properties (Abstract, Constant)
        queueAvailable;
    end
    
    properties (SetAccess = protected)
        description;
        maxRefreshRate = Inf; % [Hz], numeric
        pixelResolutionXY; % [1x2 numeric] pixel resolution of SLM
        pixelPitchXY;      % [1x2 numeric] distance from pixel center to pixel center in meter
        interPixelGapXY;   % [1x2 numeric] pixel spacing in x and y in meter
        pixelBitDepth;     % numeric, one of {8,16,32,64} corresponds to uint8, uint16, uint32, uint64 data type
        computeTransposedPhaseMask;
    end
    
    methods (Abstract, Access = protected)
        writeSlmQueue(obj,frames);
        startSlmQueue(obj);
        abortSlmQueue(obj);
    end
    
    properties (SetAccess = private)
        queueStarted = false;
    end
    
    properties (Dependent, SetAccess = private)
        pixelDataType;
        pixelPitchXY_um;
        interPixelGapXY_um;
    end
    
    methods (Abstract)
        writeBitmap(obj,phaseMaskRaw,waitForTrigger)
    end
    
    methods
        function delete(obj)
            if obj.queueStarted
                try
                    obj.abortQueue();
                catch ME
                    most.ErrorHandler.logAndReportError(ME);
                end
            end
        end
    end
    
    methods
        function val = get.pixelPitchXY_um(obj)
            val = obj.pixelPitchXY * 1e6;
        end
        
        function val = get.interPixelGapXY_um(obj)
            val = obj.interPixelGapXY * 1e6;
        end        
        
        function val = get.pixelDataType(obj)
            switch obj.pixelBitDepth
                case 8
                    val = 'uint8';
                case 16
                    val = 'uint16';
                case 32
                    val = 'uint32';
                case 64
                    val = 'uint64';
                otherwise
                    error('Unknown datatype of length %d',obj.pixelBitDepth);
            end
        end
    end
    
    %% User methods
    methods        
        function writeQueue(obj,frames)
            assert(obj.queueAvailable,'Queue is not available for SLM');
            if obj.computeTransposedPhaseMask
                assert(size(frames,2)==obj.pixelResolutionXY(2) && size(frames,1) == obj.pixelResolutionXY(1),'Incorrect frame pixel resolution');
            else
                assert(size(frames,2)==obj.pixelResolutionXY(1) && size(frames,1) == obj.pixelResolutionXY(2),'Incorrect frame pixel resolution');
            end
            frames = cast(frames,obj.pixelDataType);
            
            obj.writeSlmQueue(frames);
        end
        
        function startQueue(obj)
            assert(obj.queueAvailable,'Queue is not available for SLM');
            obj.startSlmQueue();
            obj.queueStarted = true;
        end
        
        function abortQueue(obj)
            assert(obj.queueAvailable,'Queue is not available for SLM');
            obj.queueStarted = false;
            obj.abortSlmQueue();
        end
    end
    
    methods         
         function set.maxRefreshRate(obj,val)
            validateattributes(val,{'numeric'},{'positive','nonnan','scalar'});
            obj.maxRefreshRate = val;
        end
    end
end



%--------------------------------------------------------------------------%
% SLM.m                                                                    %
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
