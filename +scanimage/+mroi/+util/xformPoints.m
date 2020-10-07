function pts = xformPoints(pts,T,inverse)
    persistent oldMatlabVersion    

    if nargin<3 || isempty(inverse)
        inverse = false;
    end

    if isempty(oldMatlabVersion)
        % implicit expansion for element wise operations was introduced in Matlab 2016b
        oldMatlabVersion = verLessThan('matlab','9.1');
    end

    identity = eye(size(T),class(pts));
    
    if isequal(T,identity)
        % special case: identity matrix
        return
    end
    
    if inverse
        T = inv(double(T));
    end
    
    T = cast(T,class(pts));
    
    isPerspective = ~isequal(T(end,:),identity(end,:));
    
    T = T';
    T_ScaleAndRotation = T(1:end-1,1:end-1);
    T_Translation      = T(end,1:end-1);
    
    if isPerspective
        T_Perspective = T(:,end);
        w = pts * T_Perspective(1:end-1) + T_Perspective(end);
    end
    
    pts = pts * T_ScaleAndRotation;
    
    if oldMatlabVersion
        pts = bsxfun(@plus,pts,T_Translation);
    else
        pts = pts + T_Translation;
    end
    
    if isPerspective
        if oldMatlabVersion
            pts = bsxfun(@rdivide,pts,w);
        else
            pts = pts ./ w;
        end
    end
end


%--------------------------------------------------------------------------%
% xformPoints.m                                                            %
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
