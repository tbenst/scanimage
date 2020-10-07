% this code was developed by Marius Pachitariu and Carsen Stringer as part of the software package Suite2p

function K = kernelD(xp0,yp0,len)

D  = size(xp0,1);
N  = size(xp0,2); 
M  = size(yp0,2);

% split M into chunks if on GPU to reduce memory usage
if isa(xp0,'gpuArray') 
    K=gpuArray.zeros(N,M);
    cs  = 60;
elseif N > 10000
    K = zeros(N,M);
    cs = 10000;
else
    K= zeros(N,M);
    cs  = M;
end

for i = 1:ceil(M/cs)
    ii = [((i-1)*cs+1):min(M,i*cs)];
    mM = length(ii);
    xp = repmat(xp0,1,1,mM);
    yp = reshape(repmat(yp0(:,ii),N,1),D,N,mM);

    Kn = exp( -sum(bsxfun(@times,(xp - yp).^2,1./(len.^2))/2,1));
    K(:,ii)  = squeeze(Kn); 
    
end


 

%--------------------------------------------------------------------------%
% kernelD.m                                                                %
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
