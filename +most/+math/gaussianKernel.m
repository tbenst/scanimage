function kernel = gaussianKernel(kernelSize,sigma)
if nargin < 1 || isempty(kernelSize)
    kernelSize = [3 3];
end

if nargin < 3 || isempty(sigma)
    sigma = kernelSize / 2;
end

if isscalar(sigma)
    sigma = repmat(sigma,1,numel(kernelSize));
end

validateattributes(sigma,{'numeric'},{'positive','row'});
validateattributes(kernelSize,{'numeric'},{'positive','row','integer'});

dims = numel(kernelSize);

vecs_squared = cell(1,dims);
for idx = 1:dims
    simSize = kernelSize(idx);
    vecs_squared{idx} = linspace(-simSize/2,simSize/2,simSize).^2;
end

grids_squared = cell(1,dims);
[grids_squared{1:end}] = ndgrid(vecs_squared{:});

sigma_squared_times_two = 2 * sigma.^2;

kernel = arrayfun(@(varargin)exp(-sum([varargin{:}] ./ sigma_squared_times_two)),grids_squared{:});
kernel = kernel ./ sum(kernel(:)); % scale to maintain unity

end

%--------------------------------------------------------------------------%
% gaussianKernel.m                                                         %
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
