function A = inPlaceTranspose(A)
ASize = size(A);
frameSize = [size(A,1), size(A,2)];
frameNumPixels = prod(frameSize);

if frameSize(1) > 1 && frameSize(2) > 1
    frame = zeros(frameSize,'like',A);
    frame = frame + 1; % to ensure nothing else references frame
    for startIdx = 1:frameNumPixels:numel(A)
        frame = reshape(frame,frameSize);
        most.memfunctions.inplacewrite(frame,A,1,startIdx,frameNumPixels);
        frame = frame';
        most.memfunctions.inplacewrite(A,frame,startIdx,1,frameNumPixels);
    end
end

A = reshape(A,ASize([2 1,3:end]));
end

%--------------------------------------------------------------------------%
% inPlaceTranspose.m                                                       %
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
