classdef CSLinear < scanimage.mroi.coordinates.CoordinateSystem
    properties
        toParentAffine = [];
        fromParentAffine = [];
    end
    
    properties (SetAccess = protected)
        forwardable = true;
        reversible = true;
    end
    
    properties (SetAccess = private, GetAccess = private)
        internalSet = false;
    end
    
    methods
        function obj = CSLinear(name,dimensions,hParent)
            if nargin < 3 || isempty(hParent)
                hParent = [];
            end
            
            obj = obj@scanimage.mroi.coordinates.CoordinateSystem(name,dimensions,hParent);
            obj.toParentAffine = diag(ones(1,dimensions+1));
        end
    end
    
    methods (Access = protected)
        function pts = applyTransforms(obj,reverse,pts)
            T = getPathTransform(obj,reverse);
            pts = scanimage.mroi.util.xformPoints(pts,T);
        end
        
        function s = toStructInternal(obj)
            s = struct();
            s.toParentAffine = obj.toParentAffine;
            s.fromParentAffine = obj.fromParentAffine;
        end
        
        function fromStructInternal(obj,s)
            if ~isempty(s.toParentAffine)
                obj.toParentAffine = s.toParentAffine;
            else
                obj.fromParentAffine = s.fromParentAffine;
            end
        end
        
        function resetInternal(obj)
            identityMatrix = eye(obj.dimensions+1);
            if ~isempty(obj.toParentAffine)
                obj.toParentAffine = identityMatrix;
            else
                obj.fromParentAffine = identityMatrix;
            end
        end
    end
    
    methods
        function disp(obj)
            builtin('disp',obj);
            fprintf('toParentAffine:\n');
            disp(obj.toParentAffine);
            fprintf('fromParentAffine:\n');
            disp(obj.fromParentAffine);
        end
    end
    
    methods
        function set.toParentAffine(obj,val)
            if obj.internalSet
                obj.toParentAffine = val;
                return
            end
            
            invertible = obj.validateAffine(val);
            
            if ~isempty(obj.fromParentAffine)
                if ~iseye(obj.fromParentAffine)
                    warning('Linear Coordinate System %s: Setting toParentAffine overwrites fromParentAffine',obj.name);
                end
                obj.internalSet = true;
                obj.fromParentAffine = [];
                obj.internalSet = false;
            end
            
            obj.forwardable = true;
            obj.reversible = invertible;
            
            oldVal = obj.toParentAffine;
            obj.toParentAffine = val;
            
            if ~isequal(oldVal,obj.toParentAffine)
                notify(obj,'changed');
            end
        end
        
        function set.fromParentAffine(obj,val)
            if obj.internalSet
                obj.fromParentAffine = val;
                return
            end
            
            invertible = obj.validateAffine(val);
            
            if ~isempty(obj.toParentAffine)
                if ~iseye(obj.toParentAffine)
                    warning('Linear Coordinate System %s: Setting fromParentAffine overwrites toParentAffine',obj.name);
                end
                obj.internalSet = true;
                obj.toParentAffine = [];
                obj.internalSet = false;
            end
            
            obj.forwardable = invertible;
            obj.reversible = true;
            
            oldVal = obj.fromParentAffine;            
            obj.fromParentAffine = val;
            
            if ~isequal(oldVal,obj.fromParentAffine)
                notify(obj,'changed');
            end
        end
    end
    
    methods (Access = private)
        function invertible = validateAffine(obj,T)
            lastRow = zeros(1,obj.dimensions(end)+1);
            
            validateattributes(T,{'numeric'},{'size',[obj.dimensions obj.dimensions]+1,'nonnan','finite'});
            
            invertible = det(T)~=0;
        end
    end
end

function T = getPathTransform(transitions,reverse)
    T = eye(transitions(1).dimensions+1);
    
    for idx = 1:numel(transitions)
        transition = transitions(idx);
        
        if reverse(idx)
            if ~isempty(transition.fromParentAffine)
                T = transition.fromParentAffine * T;
            else
                T = transition.toParentAffine \ T;
            end
        else % forward
            if ~isempty(transition.toParentAffine)
                T = transition.toParentAffine * T;
            else
                T = transition.fromParentAffine \ T;
            end
        end
    end
end

function tf = iseye(T)
    identity = eye(size(T,1));
    tf = isequal(T,identity);
end

%--------------------------------------------------------------------------%
% CSLinear.m                                                               %
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
