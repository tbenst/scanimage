classdef CSFunction < scanimage.mroi.coordinates.CoordinateSystem
    properties
        toParentFunction = [];
        fromParentFunction = [];
    end
    
    properties (SetAccess = protected)
        forwardable = true;
        reversible  = true;
    end
    
    methods
        function obj = CSFunction(name,dimensions,hParent)
            if nargin < 3 || isempty(hParent)
                hParent = [];
            end
            obj = obj@scanimage.mroi.coordinates.CoordinateSystem(name,dimensions,hParent);
        end
    end
    
    methods (Access = protected)
        function pts = applyTransforms(obj,reverse,pts)
            for idx = 1:numel(obj)
                if reverse(idx)
                    fun = obj(idx).fromParentFunction;
                else
                    fun = obj(idx).toParentFunction;
                end
                
                if ~isempty(fun)
                    pts = fun(pts);
                end
            end
        end
        
        function s = toStructInternal(obj)
            s = struct();
            
            s.toParentFunction   = str2FuncWithEmpty(obj.toParentFunction);
            s.fromParentFunction = str2FuncWithEmpty(obj.fromParentFunction);
        end
        
        function fromStructInternal(obj,s)
            % No op. Cannot load functions, but can at least check if they
            % match
            
            if ~strcmp(s.toParentFunction, str2FuncWithEmpty(obj.toParentFunction))
                warning('Coordinate System %s: Loaded toParentFunction %s does not match actual function %s.', ...
                    obj.name, s.toParentFunction, str2FuncWithEmpty(obj.toParentFunction));
            end
            
            if ~strcmp(s.fromParentFunction, str2FuncWithEmpty(obj.fromParentFunction))
                warning('Coordinate System %s: Loaded fromParentFunction %s does not match actual function %s.', ...
                    obj.name, s.fromParentFunction, str2FuncWithEmpty(obj.fromParentFunction));
            end
        end
        
        function resetInternal(obj)
            obj.toParentFunction = [];
            obj.fromParentFunction = [];
        end
    end
    
    methods        
        function set.toParentFunction(obj,val)
            oldVal = obj.toParentFunction;
            
            val = obj.validateFunction(val);
            obj.toParentFunction = val;
            
            obj.updateDirections();
            
            if ~isequal(oldVal,obj.toParentFunction)
                notify(obj,'changed');
            end
        end
        
        function set.fromParentFunction(obj,val)
            oldVal = obj.fromParentFunction;

            val = obj.validateFunction(val);
            obj.fromParentFunction = val;
            
            obj.updateDirections();
            
            if ~isequal(oldVal,obj.fromParentFunction)
                notify(obj,'changed');
            end
        end
    end
    
    methods (Access = private)
        function val = validateFunction(obj,val)
            if isempty(val)
                val = [];
            else
                validateattributes(val,{'function_handle'},{'scalar'});
                testFunction(val); 
            end
            
            function testFunction(val)
                pts = zeros(10,obj.dimensions);
                try
                    pts_ = val(pts);
                catch ME
                    fprintf(2,'Cannot execute function %s\n', func2str(val));
                    rethrow(ME);                    
                end
                assert(isequal(size(pts_),size(pts)),'Function %s does not return the correct array size', func2str(val));
            end
        end
        
        function updateDirections(obj)
            obj.forwardable = ~isempty(obj.toParentFunction) || ...
                              (isempty(obj.toParentFunction) && isempty(obj.fromParentFunction));
                          
            obj.reversible = ~isempty(obj.fromParentFunction) || ...
                              (isempty(obj.toParentFunction) && isempty(obj.fromParentFunction));
        end
    end
end

function str = str2FuncWithEmpty(fcnHdl)
    if isempty(fcnHdl)
        str = '';
    else
        str = func2str(fcnHdl);
    end
end

%--------------------------------------------------------------------------%
% CSFunction.m                                                             %
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
