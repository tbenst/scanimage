classdef Points
    properties (SetAccess = immutable)
        hCoordinateSystem
        points
        numPoints
        dimensions
        UserData
    end
    
    methods
        function obj = Points(hCoordinateSystem,points,UserData)
            if nargin < 3 || isempty(UserData)
                UserData = [];
            end
            
            assert(isa(hCoordinateSystem,'scanimage.mroi.coordinates.CoordinateSystem'),'Not a valid scanimage.mroi.coordinates.CoordinateSystem');
            assert(isscalar(hCoordinateSystem) && isvalid(hCoordinateSystem));
            
            assert(isnumeric(points) && size(points,2)==hCoordinateSystem.dimensions,'Points do not have same number of dimensions as coordinate system.');
            
            obj.hCoordinateSystem = hCoordinateSystem;
            obj.points = points;
            obj.numPoints = size(points,1);
            obj.dimensions = size(points,2);
            obj.UserData = UserData;
        end
        
        function objs = transform(objs,hCoordinateSystem)
            assert(isa(hCoordinateSystem,'scanimage.mroi.coordinates.CoordinateSystem'));
            assert(isscalar(hCoordinateSystem) && isvalid(hCoordinateSystem));
            
            for idx = 1:numel(objs)
                objs(idx) = hCoordinateSystem.transform(objs(idx));
            end
        end
        
        function objs = subset(objs,idxs)
            for idx = 1:numel(objs)
                obj = objs(idx);
                pts = obj.points(idxs,:);
                objs(idx) = scanimage.mroi.coordinates.Points(obj.hCoordinateSystem,pts,obj.UserData);
            end
        end
        
        function disp(objs)
            if isscalar(objs)
                fprintf('Coordinate System: %s (%s)\n',objs.hCoordinateSystem.name,class(objs.hCoordinateSystem));
                fprintf('\tNumber Of Points: %d\n\n',objs.numPoints);
                
                if objs.numPoints < 50
                    disp(objs.points);
                else
                    disp(objs.points(1:10,:));
                    fprintf('... [truncated %d points] ...\n\n',objs.numPoints-20);
                    disp(objs.points(end-9:end,:));
                end
            else
                c = class(objs);
                sizeStr = sprintf('%d×',size(objs));
                sizeStr(end) = []; % delete last ×
                fprintf('%s array of %s\n\n',sizeStr,c);
            end
        end
        
        function hPts = insert(obj,pts,idx)
            assert(isscalar(obj));
            
            if isa(pts,class(obj))
                pts = pts.transform(obj.hCoordinateSystem);
                pts = pts.points;
            end
            
            before = obj.points(1:idx-1,:);
            after  = obj.points(idx:end,:);
            
            pts = vertcat(before,pts,after);
            
            hPts = scanimage.mroi.coordinates.Points(obj.hCoordinateSystem,pts,obj.UserData);
        end
        
        function hPts = append(obj,pts)
            assert(isscalar(obj));
            
            if isa(pts,class(obj))
                pts = pts.transform(obj.hCoordinateSystem);
                pts = pts.points;
            end
            
            pts = vertcat(obj.points,pts);
            
            hPts = scanimage.mroi.coordinates.Points(obj.hCoordinateSystem,pts,obj.UserData);
        end
        
        function hPts = remove(obj,idxs)
            assert(isscalar(obj));
            
            pts = obj.points;
            pts(idxs,:) = [];
            
            hPts = scanimage.mroi.coordinates.Points(obj.hCoordinateSystem,pts,obj.UserData);
        end
        
        function hPts = filter(obj,idxs)
            assert(isscalar(obj));
            
            pts = obj.points;
            pts = pts(idxs,:);
            
            hPts = scanimage.mroi.coordinates.Points(obj.hCoordinateSystem,pts,obj.UserData);
        end
    end
end

%--------------------------------------------------------------------------%
% Points.m                                                                 %
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
