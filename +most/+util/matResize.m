function outputMatrix = matResize(inputMatrix,scale)
%MATRESIZE Resizes a matrix.
%
% inputMatrix: the matrix data to resize.
% 
% scale: either a scalar factor by which to scale the matrix, or a 2-vector
% indicating [numRows,numCols] of the output matrix.
        
    if nargin < 2 || isempty(scale)
        error('Insufficient arguments');
    end

    if isscalar(scale)
        mNew = floor(size(inputMatrix,1)/scale);
        nNew = floor(size(inputMatrix,2)/scale);
    elseif length(scale) == 2
        mNew = scale(1);
        nNew = scale(2);
    else
        error('Invalid argument.');
    end
    
    [m,n,~] = size(inputMatrix);
    [X,Y] = meshgrid( (0:n-1)/(n-1), (0:m-1)/(m-1) );
    [XI,YI] = meshgrid( (0:nNew-1)/(nNew-1) , (0:mNew-1)/(mNew-1) );
    outputMatrix = zeros(mNew,nNew,size(inputMatrix,3));
    for i = 1:size(inputMatrix,3)
        outputMatrix(:,:,i) = max(interp2(X,Y,inputMatrix(:,:,i),XI,YI,'cubic',0),0.0); % max() clamps any values < 0.0
    end

end



%--------------------------------------------------------------------------%
% matResize.m                                                              %
% Copyright � 2020 Vidrio Technologies, LLC                                %
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
