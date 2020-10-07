classdef polynomialInterpolant < handle
    % most.math.polynomialInterpolant(X,v) mimicks scatteredInterpolant
    % but uses most.math.polyfitn as the backend. see most.math.polyfitn
    % for description of parameter 'modelterms'
    %
    %   F = most.math.polynomialInterpolant(X,v) creates an interpolant that fits a
    %   surface of the form v = F(X) to the sample data set (X,v). The sample
    %   points X must have size NPTS-by-N in N-D, where NPTS is the number
    %   of points. Each row of X contains the coordinates of one sample point.
    %  The values v must be a column vector of length NPTS.
    %
    %   F = most.math.polynomialInterpolant(...,modelterms) specifies model
    %   terms for the polynomial fits. See most.math.polyfitn for details
    %
    %   polynomialInterpolant methods:
    %       vq = F(Xq) evaluates the scatteredInterpolant F at scattered query
    %       points Xq and returns a column vector of interpolated values vq.
    %       Each row of Xq contains the coordinates of one query point.
    %
    %       vq = F(D1q,D2q,...DNq)  also allow the scattered query
    %       points to be specified as column vectors of coordinates.
    
    properties
        Points = [];
        Values = [];
        ModelTerms = [];
    end
    
    properties (Hidden, SetAccess = private)
        polymodel;
    end
    
    methods
        function obj = polynomialInterpolant(X,v,modelterms)
            if nargin < 1 || isempty(X)
                X = [];
            end
            
            if nargin < 2 || isempty(v)
                v = [];
            end
            
            if nargin < 3 || isempty(modelterms)
                modelterms = [];
            end
            
            obj.Points = X;
            obj.Values = v;
            obj.ModelTerms = modelterms;
            
            if ~isempty(obj.Points) || ~isempty(obj.Values)
                obj.validateParameters();
            end
        end
    end
    
    methods
        function B = subsref(A,S)
            if numel(A)==1 && numel(S)==1 && strcmp(S.type,'()')
                B = A.interpolate(S.subs{:});
            else
                B = builtin('subsref',A,S);
            end
        end
        
        function v = interpolate(obj,varargin)
            points = horzcat(varargin{:});
            
            if isempty(obj.polymodel)
                obj.createPolyModel();
            end
            
            v = most.math.polyvaln(obj.polymodel,points);
        end
        
        function s = toStruct(obj)
            s = struct();
            s.Points = obj.Points;
            s.Values = obj.Values;
            s.ModelTerms = obj.ModelTerms;
        end
        
        function fromStruct(obj,s)
            obj.Points = s.Points;
            obj.Values = s.Values;
            obj.ModelTerms = s.ModelTerms;
        end
    end
    
    methods (Access = private)
        function createPolyModel(obj)
            obj.validateParameters();
            
            if isempty(obj.ModelTerms)
                modelTerms = size(obj.Points,2)-1;
            else
                modelTerms = obj.ModelTerms;
            end
            
            obj.polymodel = most.math.polyfitn(obj.Points,obj.Values,modelTerms);
        end
        
        function validateParameters(obj)
            assert(any(strcmp(class(obj.Points),{'single','double'})),'Points must be of class single or double');
            assert(any(strcmp(class(obj.Values),{'single','double'})),'Points must be of class single or double');
            assert(any(strcmp(class(obj.ModelTerms),{'single','double'})),'ModelTerms must be of class single or double');
            
            assert(~isempty(obj.Points) && ~isempty(obj.Values),'Points and Values cannot be empty');
            assert(size(obj.Points,1)==size(obj.Values,1),'Points and Values must have same number of entries');
            
            assert(size(obj.Values,2)==1,'Values must be a column vector');
        end
    end
    
    methods
        function set.Points(obj,val)
            if ~isequal(obj.Points,val)
                obj.Points = val;
                obj.polymodel = [];
            end
        end
        
        function set.Values(obj,val)
            if ~isequal(obj.Values,val)
                obj.Values = val;
                obj.polymodel = [];
            end
        end
        
        function set.ModelTerms(obj,val)
            if ~isequal(obj.ModelTerms,val)
                obj.ModelTerms = val;
                obj.polymodel = [];
            end
        end
    end
end

%--------------------------------------------------------------------------%
% polynomialInterpolant.m                                                  %
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
