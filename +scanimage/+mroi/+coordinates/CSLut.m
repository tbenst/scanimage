classdef CSLut < scanimage.mroi.coordinates.CoordinateSystem
    properties
        toParentInterpolant = {};
        fromParentInterpolant = {};
    end
    
    properties (SetAccess = protected)
        forwardable = true;
        reversible  = true;
    end
    
    methods
        function obj = CSLut(name,dimensions,hParent)
            if nargin < 3 || isempty(hParent)
                hParent = [];
            end
            obj = obj@scanimage.mroi.coordinates.CoordinateSystem(name,dimensions,hParent);
            
            obj.toParentInterpolant   = cell(1,obj.dimensions);
            obj.fromParentInterpolant = cell(1,obj.dimensions);
        end
    end
    
    methods (Access = protected)
        function pts = applyTransforms(obj,reverse,pts)            
            for idx = 1:numel(obj)
                if reverse(idx)
                    interpolant = obj(idx).fromParentInterpolant;
                else
                    interpolant = obj(idx).toParentInterpolant;
                end
                
                if ~isempty(interpolant)
                    pts_temp = pts;
                    for dim_idx = 1:numel(interpolant)
                        dimInterpolant = interpolant{dim_idx};
                        if ~isempty(dimInterpolant)
                            singularDimension = ( isa(dimInterpolant,'griddedInterpolant') && numel(dimInterpolant.GridVectors) == 1 ) || ...
                                                 ~isa(dimInterpolant,'griddedInterpolant') && size(dimInterpolant.Points,2) == 1;
                            
                            if singularDimension
                                pts(:,dim_idx) = dimInterpolant(pts_temp(:,dim_idx));
                            else
                                pts(:,dim_idx) = dimInterpolant(pts_temp);
                            end
                        end
                    end
                end
            end
        end
        
        function s = toStructInternal(obj)
            s = struct();
            s.toParentInterpolant = cellfun(@(hInterpolant)interpolantToStruct(hInterpolant),obj.toParentInterpolant,'UniformOutput',false);
            s.fromParentInterpolant = cellfun(@(hInterpolant)interpolantToStruct(hInterpolant),obj.fromParentInterpolant,'UniformOutput',false);
            
            function s = interpolantToStruct(hInterpolant)
                if isempty(hInterpolant)
                    s = struct.empty(1,0);
                else
                    s = struct();
                    switch class(hInterpolant)
                        case 'griddedInterpolant'
                            s.GridVectors = hInterpolant.GridVectors();
                            s.Values = hInterpolant.Values;
                            s.Method = hInterpolant.Method;
                            s.ExtrapolationMethod = hInterpolant.ExtrapolationMethod;
                        case 'most.math.polynomialInterpolant'
                            s = hInterpolant.toStruct();
                        case 'scatteredInterpolant'
                            s.Points = hInterpolant.Points;
                            s.Values = hInterpolant.Values;
                            s.Method = hInterpolant.Method;
                            s.ExtrapolationMethod = hInterpolant.ExtrapolationMethod;
                        otherwise
                            error('Converting %s to struct not implemented',class(hInterpolant));
                    end
                    s.class = class(hInterpolant);
                end
            end
        end
        
        function fromStructInternal(obj,s)
            obj.toParentInterpolant = cellfun(@(s)structToInterpolant(s),s.toParentInterpolant,'UniformOutput',false);
            obj.fromParentInterpolant = cellfun(@(s)structToInterpolant(s),s.fromParentInterpolant,'UniformOutput',false);
            
            function hInterpolant = structToInterpolant(s)
                if isempty(s)
                    hInterpolant = [];
                else
                    constructorFcnhdl = str2func(s.class);
                    hInterpolant = constructorFcnhdl();
                    s = rmfield(s,'class');
                    fields = fieldnames(s);
                    
                    for idx = 1:numel(fields)
                        field = fields{idx};
                        hInterpolant.(field) = s.(field);
                    end
                end
            end
        end
        
        function resetInternal(obj)
            obj.toParentInterpolant = {};
            obj.fromParentInterpolant = {};
        end
    end
    
    methods        
        function set.toParentInterpolant(obj,val)
            oldVal = obj.toParentInterpolant;
            
            val = obj.validateInterpolant(val);
            obj.toParentInterpolant = val;
            
            obj.updateDirections();
            
            if ~isequal(oldVal,obj.toParentInterpolant)
                notify(obj,'changed');
            end
        end
        
        function set.fromParentInterpolant(obj,val)
            oldVal = obj.fromParentInterpolant;
            
            val = obj.validateInterpolant(val);
            obj.fromParentInterpolant = val;
            
            obj.updateDirections();
            
            if ~isequal(oldVal,obj.fromParentInterpolant)
                notify(obj,'changed');
            end
        end
    end
    
    methods (Access = private)
        function val = validateInterpolant(obj,val)
            if isempty(val)
                val = cell(1,obj.dimensions);
            else
                validateattributes(val,{'cell'},{'vector','size',[1,obj.dimensions]});
                
                for idx = 1:numel(val)
                    v = val{idx};
                    if ~isempty(v)
                        assert(isscalar(v));
                        
                        switch class(v)
                            case 'griddedInterpolant'
                                gridDimensions = numel(v.GridVectors);
                                assert(gridDimensions==1 || gridDimensions==obj.dimensions,...
                                    'Gridded Interpolant has incorrect number of dimensions. Expected: 1 OR %d; Actual: %d',...
                                    obj.dimensions,gridDimensions);
                                
                            case {'scatteredInterpolant', 'most.math.polynomialInterpolant'}
                                pointDimensions = size(v.Points,2);
                                assert(pointDimensions==obj.dimensions,...
                                    'Interpolant has incorrect number of dimensions. Expected: %d; Actual: %d',...
                                    obj.dimensions,pointDimensions);                                
                                
                            otherwise
                                error('Interpolant must be of type {''griddedInterpolant'' ''scatteredInterpolant'' ''most.math.polynomialInterpolant'' }');
                        end                        
                    end                    
                end
            end 
        end
        
        function updateDirections(obj)
            obj.forwardable = ~isempty(obj.toParentInterpolant) || ...
                              (isempty(obj.toParentInterpolant) && isempty(obj.fromParentInterpolant));
                          
            obj.reversible = ~isempty(obj.fromParentInterpolant) || ...
                              (isempty(obj.toParentInterpolant) && isempty(obj.fromParentInterpolant));
        end
    end
end

%--------------------------------------------------------------------------%
% CSLut.m                                                                  %
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
