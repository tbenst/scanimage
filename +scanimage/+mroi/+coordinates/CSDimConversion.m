classdef CSDimConversion < scanimage.mroi.coordinates.CoordinateSystem
    properties (SetAccess = private)
        parentDimensions;
    end
     
    properties (SetAccess = immutable)
        dimensionSelection;
    end
    
    properties (SetAccess = protected)
        forwardable = true;
        reversible = true;
    end
    
    methods
        function obj = CSDimConversion(name,dimensions,hParent,parentDimensions,dimensionSelection)
            obj = obj@scanimage.mroi.coordinates.CoordinateSystem(name,dimensions,[]);
            
            if nargin < 5 || isempty(dimensionSelection)
               dimensionSelection = 1:min(dimensions,parentDimensions);
            end
            
            validateattributes(dimensionSelection,{'numeric'},{'vector','integer','positive'});
            validateattributes(parentDimensions,  {'numeric'},{'scalar','integer','positive'});
            
            minDimNum = min(dimensions,parentDimensions);
            assert(numel(dimensionSelection) == minDimNum,'dimensionSelection must have %d number of elements.',minDimNum);
            assert(all(dimensionSelection <= minDimNum),'All elements of dimensionSelection need to be smaller or equal to %d.',minDimNum);
            
            obj.parentDimensions = parentDimensions;
            obj.dimensionSelection = dimensionSelection;
            
            obj.hParent = hParent;
        end
        
        function delete(obj)
        end
    end
    
    methods (Access = protected)
        function pts = applyTransforms(obj,reverse,pts)
            numPoints = size(pts,1);
            
            for idx = 1:numel(obj)
                if ~reverse(idx)
                    if obj(idx).dimensions >= obj(idx).parentDimensions
                        pts = pts(:,obj(idx).dimensionSelection);
                    else
                        pts_ = zeros(numPoints,obj(idx).parentDimensions,'like',pts);
                        pts_(:,obj(idx).dimensionSelection) = pts;
                        pts = pts_;
                    end
                else
                    if obj(idx).dimensions <= obj(idx).parentDimensions
                        pts = pts(:,obj(idx).dimensionSelection);
                    else
                        pts_ = zeros(numPoints,obj(idx).dimensions,'like',pts);
                        pts_(:,obj(idx).dimensionSelection) = pts;
                        pts = pts_;
                    end
                end
            end
        end
        
        function s = toStructInternal(obj)
            s = struct();
            s.parentDimensions   = obj.parentDimensions;
            s.dimensionSelection = obj.dimensionSelection;
        end
        
        function fromStructInternal(obj,s)
            % Cannot load properties, since they need are parameters of
            % constructor and are immutable. Just check and issue warning
            % if params do not match
            
            if ~isequal(s.parentDimensions,obj.parentDimensions)
                warning('Coordinate System %s');
            end
            
            if ~isequal(s.dimensionSelection,obj.dimensionSelection)
                
            end
        end
        
        function resetInternal(obj)
            % No-op
        end
    end
    
    methods (Access = protected)
        function validateParentCS(obj,hNewParent)            
            assert(hNewParent.dimensions == obj.parentDimensions, ...
                'Dimensions mismatch between coordinatesystems. Expected %s to have %d dimensions; instead it has %d dimensions', ...
                hNewParent.name, obj.parentDimensions, hNewParent.dimensions);
        end
    end
end


%--------------------------------------------------------------------------%
% CSDimConversion.m                                                        %
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
