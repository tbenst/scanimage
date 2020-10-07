classdef SLMRemote < handle    
    properties (SetAccess = protected)
        hClient;
        hDevice;
        queueAvailable;
        description;
        maxRefreshRate;       % [Hz], numeric
        pixelResolutionXY;    % [1x2 numeric] pixel resolution of SLM
        pixelPitchXY;         % [1x2 numeric] distance from pixel center to pixel center in meters
        pixelPitchXY_um;      % [1x2 numeric] distance from pixel center to pixel center in meters
        interPixelGapXY;      % [1x2 numeric] pixel spacing in x and y
        interPixelGapXY_um;   % [1x2 numeric] pixel spacing in x and y
        pixelBitDepth;        % numeric, one of {8,16,32,64} corresponds to uint8, uint16, uint32, uint64 data type
        computeTransposedPhaseMask;
        pixelDataType;
        queueStarted = false;
    end
    
    properties (Dependent)
        
    end
    
    methods
        function obj = SLMRemote(hSLM)
            assert(isa(hSLM,'most.network.matlabRemote.ServerVar'));
            obj.hDevice = hSLM;
            obj.hClient = hSLM.hClient__;
            
            % cache constant properties
            retrieveProperty('queueAvailable');
            retrieveProperty('description');
            retrieveProperty('maxRefreshRate');
            retrieveProperty('pixelResolutionXY');
            retrieveProperty('pixelPitchXY');
            retrieveProperty('pixelPitchXY_um');
            retrieveProperty('interPixelGapXY');
            retrieveProperty('interPixelGapXY_um');
            retrieveProperty('pixelBitDepth');
            retrieveProperty('computeTransposedPhaseMask');
            retrieveProperty('pixelDataType');            
            
            function retrieveProperty(propertyName)
                var = obj.hDevice.(propertyName);
                obj.(propertyName) = var.download();
            end
        end
        
        function delete(obj)
            obj.hClient.feval('delete',obj.hDevice);
            obj.hDevice = [];
        end
    end
    
    %% User methods
    methods        
        function writeBitmap(obj,varargin)
            obj.hDevice.writeBitmap(varargin{:});
        end
        
        function writeQueue(obj,varargin)
            obj.hDevice.writeQueue(varargin{:});
        end
        
        function startQueue(obj)
            obj.hDevice.startQueue();
            obj.queueStarted = true;
        end
        
        function abortQueue(obj)
            obj.hDevice.abortQueue();
            obj.queueStarted = false;
        end
    end
end



%--------------------------------------------------------------------------%
% SLMRemote.m                                                              %
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
