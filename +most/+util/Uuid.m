classdef Uuid < handle
    % simple class that defines a uuid
    % inherit from this class to uniquley identify objects without relying
    % on equality of handlesw
    
    properties (SetAccess = immutable, Hidden)
        uuiduint64 % uint64: represents the first 8 bytes from the uuid. should still be unique for all practical purposes
        uuid       % string: human readable uuid
    end
    
    methods
        function obj = Uuid()
            [obj.uuiduint64,obj.uuid] = most.util.generateUUIDuint64();
        end
    end
    
    methods (Hidden)
        function tf = isequal(obj,other)
            tf = isa(other,class(obj));
            tf = tf && isequal(size(obj),size(other));
            tf = tf && all(isequal([obj(:).uuiduint64],[other(:).uuiduint64]));
        end
        
        function tf = eq(obj,other)             
            if isa(other,class(obj))
                obj   = reshape([  obj(:).uuiduint64],size(obj));
                other = reshape([other(:).uuiduint64],size(other));
            else
                % making obj true and other false will make the following
                % equal check return false
                obj   = true(size(obj));
                other = false(size(other));
            end
            
            tf = obj==other;
        end
        
        function tf = neq(obj,other)
            tf = ~obj.eq(other);
        end
        
        function tf = uuidcmp(obj,other)
            thisclassname = mfilename('class');
            
            if numel(obj)==0 || numel(other)==0
                tf = [];
            elseif isscalar(obj) && iscell(other)
                validationFcn = @(o)isa(o,thisclassname) && isscalar(o) && obj.uuidcmp(o); % don't check for validity here (checked in getUuid below)
                tf = cellfun(validationFcn,other);
            else
                assert(isa(other,thisclassname),'Expected input to be a ''%s''',thisclassname);
                assert(numel(obj)==1 || numel(other)==1,'Expected one input to be scalar');
                tf = arrayfun(@getUuid,obj) == arrayfun(@getUuid,other);
            end
            
            function uuid = getUuid(obj)
                % workaround for isvalid function behavior:
                % isvalid returns false if called within an object's delete
                % function. There is no good way to check if an object is
                % actually invalid or if we are still inside the delete
                % function. All we can do is to query a property and see if it
                % errors
                try
                    uuid = obj.uuiduint64;
                catch
                    uuid = NaN; % the object is not valid anymore
                end
            end
        end
    end    
end



%--------------------------------------------------------------------------%
% Uuid.m                                                                   %
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
