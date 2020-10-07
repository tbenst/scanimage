% this code was developed by Marius Pachitariu and Carsen Stringer as part of the software package Suite2p

function batchSize = getBatchSize(nPixels)

g = gpuDevice;

batchSize = 2^(floor(log2(8e9))-6)/2^ceil(log2(nPixels));
if any(strcmp(fields(g), 'AvailableMemory'))
  batchSize = 2^(floor(log2(g.AvailableMemory))-6)/2^ceil(log2(nPixels));
elseif any(strcmp(fields(g), 'FreeMemory'))
  batchSize = 2^(floor(log2(g.FreeMemory))-6)/2^ceil(log2(nPixels));
end

% The calculation was deducted from the following examples
% batchSize = 2^25/2^ceil(log2(nPixels)); % works well on GTX 970 (which has 4 GB memory)
% batchSize = 2^23/2^ceil(log2(nPixels)); % works well on GTX 560 Ti (which has 1 GB memory)


%--------------------------------------------------------------------------%
% getBatchSize.m                                                           %
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
